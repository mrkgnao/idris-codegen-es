module BrowserTemplate

import Js.BrowserDom
import public Js.ASync


public export
data Style = MkStyle String String
           | CompStyle (List Style)

mutual
  styleStr' : Style -> String
  styleStr' (MkStyle k x) = k ++ ":" ++ x ++ ";"
  styleStr' (CompStyle x) = styleStr x

  styleStr : List Style -> String
  styleStr x = foldl (\z,w => z ++ styleStr' w) "" x


public export
data Gen a b = GenConst b | GenA (a->b)

public export
interface IGen c a b where
  getGen : c -> Gen a b

export
IGen b a b where
  getGen x = GenConst x

export
IGen (a -> b) a b where
  getGen x = GenA x

export
Functor (Gen a) where
  map f (GenConst x) = GenConst (f x)
  map f (GenA x) = GenA (f . x)

export
Applicative (Gen a) where
  pure = GenConst

  (<*>) (GenConst f) fa = f <$> fa
  (<*>) (GenA f) (GenA fa) = GenA (\x => (f x) (fa x))
  (<*>) (GenA f) (GenConst fa) = GenA (\x => (f x) fa)



data InputType = IText

inputTypeTy : InputType -> Type
inputTypeTy IText = String


public export
data Attribute : Type -> Type -> Type where
  EventClick : (a -> b) -> Attribute a b
  StrAttribute : String -> Gen a String -> Attribute a b

public export
data InputAttribute : Type -> Type -> Type -> Type where
  GenAttr : Attribute a b -> InputAttribute a b c
  OnChange : (a -> c -> b) -> InputAttribute a b c
  DynSetVal : (a -> Maybe c) -> InputAttribute a b c


public export
data FoldAttribute : Type -> Type -> Type -> Type -> Type where
  OnEvent : (a -> r -> b) -> FoldAttribute a b s r
  DynSetState : (a -> Maybe s) -> FoldAttribute a b s r


export
data Template : Type -> Type -> Type where
  CustomNode : String -> List (Attribute a b) -> List (Template a b) -> Template a b
  TextNode : List (Attribute a b) -> String -> Template a b
  DynTextNode : List (Attribute a b) ->
                  (a -> String) -> Template a b
  InputNode : (t:InputType) -> List (InputAttribute a b (inputTypeTy t)) ->
                  Template a b
  FoldNode : s -> (s->i->(s,Maybe r)) -> Template s i -> List (FoldAttribute a b s r) -> Template a b
  FormNode : (a -> b) -> List (Attribute a b) -> List (Template a b) -> Template a b
  ListTemplateNode : String -> List (Attribute a b) -> (a -> List c) ->
                          Template c b -> Template a b
  ImgNode : List (Attribute a b) -> String -> Template a b
  ContraMapNode : (a -> b) -> Template b c -> Template a c
  EmptyNode : Template a b
  CaseNode : DecEq i => String -> List (Attribute a b) -> (f : i -> Type) ->  (a->DPair i f) ->
                          ((x:i) -> Template (f x) b) -> Template a b

data Update : Type -> Type where
  MkUpdate : (a -> b) -> (b -> b -> JS_IO ()) -> Update a

Remove : Type
Remove = JS_IO ()

Updates : Type -> Type
Updates a = List (Update a)

mapUpdates : (a->b) -> (Remove, Updates b) -> (Remove, Updates a)
mapUpdates f (r,upds) = (r, map (\(MkUpdate g h)=>MkUpdate (g . f) h) upds)

procChange : JS_IO a -> (b -> JS_IO ()) ->
                  (String -> c) -> (a -> c -> b) -> String -> JS_IO ()
procChange get pr j h str =
  do
    x <- get
    pr (h x (j str))

procClick : JS_IO a -> (b -> JS_IO ()) -> (a -> b) -> () -> JS_IO ()
procClick get pr h () =
  do
    x <- get
    pr (h x)

updateStrAttribute : DomNode -> String -> String -> String -> JS_IO ()
updateStrAttribute n name x1 x2 =
  if x1 == x2 then pure ()
    else setAttribute n (name, x2)

initAttribute : a -> DomNode -> JS_IO a -> (b -> JS_IO ()) -> Attribute a b -> JS_IO (Maybe (Update a))
initAttribute _ n getst proc (EventClick h) =
  do
    registEvent (procClick getst proc h) n "click" (pure ())
    pure Nothing
initAttribute _ n getst proc (StrAttribute name (GenConst x) ) =
  do
    setAttribute n (name, x)
    pure Nothing
initAttribute v n getst proc (StrAttribute name (GenA x) ) =
  do
    setAttribute n (name, x v)
    pure $ Just $ MkUpdate x (updateStrAttribute n name)

initAttributes : a -> DomNode -> JS_IO a -> (b -> JS_IO ()) -> List (Attribute a b) -> JS_IO (List (Update a))
initAttributes v n getst proc attrs = (catMaybes<$>) $ sequence $ map (initAttribute v n getst proc) attrs

procSetVal : DomNode -> Maybe String -> JS_IO ()
procSetVal _ Nothing = pure ()
procSetVal n (Just z) =
  setValue z n

initAttributeInp : a -> DomNode -> JS_IO a -> (b -> JS_IO ()) ->
                      (String -> c) -> (c -> String) -> InputAttribute a b c -> JS_IO (Maybe (Update a))
initAttributeInp v n getst proc _ _ (GenAttr x) =
    initAttribute v n getst proc x
initAttributeInp _ n getst proc f _ (OnChange h) =
  do
    registEvent (procChange getst proc f h) n "change" targetValue
    pure Nothing
initAttributeInp v n getst proc _ f (DynSetVal h) =
  do
    procSetVal n (f <$> h v)
    pure $ Just $ MkUpdate ((f<$>) . h) (\_,y=> procSetVal n y)

initAttributesInp : a -> DomNode -> JS_IO a -> (b -> JS_IO ()) ->
                      (String -> y) -> (y -> String) -> List (InputAttribute a b y) -> JS_IO (List (Update a))
initAttributesInp v n getst proc f j attrs =
  (catMaybes<$>) $ sequence $ map (initAttributeInp v n getst proc f j) attrs

export
data TemplateState : Type -> Type where
  MkTemplateState : DomNode -> a -> Updates a -> TemplateState a

procUpdate : a -> a -> Update a -> JS_IO ()
procUpdate old new (MkUpdate r u) =
  u (r old) (r new)

procUpdates : a -> a -> Updates a -> JS_IO ()
procUpdates oz z upds = sequence_ $ map (procUpdate oz z) upds


setState : Ctx (Updates b) -> Ctx b -> Maybe b -> Maybe b -> JS_IO ()
setState _ _ _ Nothing = pure ()
setState ctxU ctxS _ (Just z) =
  do
    oz <- getCtx ctxS
    setCtx ctxS z
    upds <- getCtx ctxU
    procUpdates oz z upds

procOnEvent : JS_IO a -> (b -> JS_IO ()) -> r ->
                  List (FoldAttribute a b s r) -> JS_IO ()
procOnEvent _ _ _ [] =
  pure ()
procOnEvent geta proc z ((OnEvent h)::r) =
  do
    x <- geta
    proc (h x z)
procOnEvent geta proc z ((DynSetState h)::r) =
  procOnEvent geta proc z r

calcFoldUpdatesList: Ctx (Updates s) -> Ctx s -> List (FoldAttribute a b s r) -> Updates a
calcFoldUpdatesList _ _ Nil = []
calcFoldUpdatesList x y ((OnEvent _)::r) = calcFoldUpdatesList x y r
calcFoldUpdatesList x y ((DynSetState h)::_) =
  [MkUpdate h (setState x y)]


updateFold : Ctx (Updates s) -> Ctx s -> (s->i->(s,Maybe r)) ->
              JS_IO a -> List (FoldAttribute a b s r) -> (b -> JS_IO ()) ->
                i -> JS_IO ()
updateFold ctxU ctxS updfn geta attrs proc e =
  do
    st <- getCtx ctxS
    let (newst, mr) = updfn st e
    setCtx ctxS newst
    upds <- getCtx ctxU
    procUpdates st newst upds
    case mr of
      Nothing => pure ()
      Just x => procOnEvent geta proc x attrs

removeListNodes : List (Remove, Updates a) -> JS_IO ()
removeListNodes x =
  sequence_ $ map fst x

mutual

  updateListTemplate : Nat -> DomNode -> JS_IO a ->
                            (b -> JS_IO ()) -> (a -> List c) ->
                              Template c b ->
                                List c -> List c -> List (Remove, Updates c) -> JS_IO (List (Remove, Updates c))
  updateListTemplate pos nd getst proc h t (x::xs) (y::ys) ((r,u)::us) =
    do
      procUpdates x y u
      us' <- updateListTemplate (S pos) nd getst proc h t xs ys us
      pure $ (r,u)::us'
  updateListTemplate pos nd getst proc h t [] ys [] =
    addListTemplateNodes pos nd getst proc h t ys
  updateListTemplate pos nd getst proc h t xs [] us =
    do
      removeListNodes us
      pure []


  updateLT : DomNode -> JS_IO a ->
              (b -> JS_IO ()) -> (a -> List c) ->
                  Template c b -> Ctx (List (Remove,Updates c)) ->
                    a -> a -> JS_IO ()
  updateLT nd getst proc h t ctx o n =
    do
      upds <- getCtx ctx
      upds' <- updateListTemplate 0 nd getst proc h t (h o) (h n) upds
      setCtx ctx upds'

  addListTemplateNodes : Nat -> DomNode -> JS_IO a ->
                            (b -> JS_IO ()) -> (a -> List c) ->
                              Template c b -> List c -> JS_IO (List (Remove, Updates c))
  addListTemplateNodes {a} {c} pos nd getst proc h t [] = pure []
  addListTemplateNodes {a} {c} pos nd getst proc h t (x::xs) =
    do
      us <- initTemplate' nd x (getstAux <$> getst) proc t
      us' <- addListTemplateNodes (S pos) nd getst proc h t xs
      pure $ us :: us'
    where
      getstAux : a -> c
      getstAux x =
        case index' pos $ h x of
          Just y => y

  initChilds : DomNode -> a -> JS_IO a -> (b -> JS_IO ()) -> List (Template a b) -> JS_IO (Remove, Updates a)
  initChilds n v getst proc childs =
    do
      w <- (sequence $ map (initTemplate' n v getst proc) childs)
      pure (sequence_ $ map fst w, concat $ map snd w)

  updateCaseNode : DecEq i => DomNode -> (f : i -> Type) -> (a->DPair i f) -> JS_IO a ->
                                (b -> JS_IO ()) -> ((x:i) -> Template (f x) b) ->
                                  Ctx Remove -> Ctx (DPair i (Updates . f)) -> Update a
  updateCaseNode n f h getst proc templs ctxR ctxU =
    MkUpdate id upd
    where
      updEq : (x:i) -> f x -> f x -> JS_IO ()
      updEq x y y' =
        do
          (x' ** upds) <- getCtx ctxU
          case decEq x x' of
            Yes Refl => procUpdates y y' upds

      getTheSt : (x:i) -> JS_IO (DPair i f) -> JS_IO (f x)
      getTheSt x get =
        do
          (x' ** z') <- get
          case decEq x x' of
            Yes Refl => pure z'

      upd' : DPair i f -> DPair i f -> JS_IO ()
      upd' (x ** z) (x' ** z') =
        case decEq x x' of
          Yes Refl => updEq x z z'
          No _ =>
            do
              r <- getCtx ctxR
              r
              (r', u) <- initTemplate' n z' (getTheSt x' (h <$> getst)) proc (templs x')
              setCtx ctxR r'
              setCtx ctxU (x' ** u)

      upd : a -> a -> JS_IO ()
      upd x y = upd' (h x) (h y)


  initTemplate' : DomNode -> a -> JS_IO a -> (b -> JS_IO ()) -> Template a b -> JS_IO (Remove, Updates a)
  initTemplate' n v getst proc (CustomNode tag attrs childs) =
    do
      newn <- appendNode n tag
      attrsUpds <- initAttributes v newn getst proc attrs
      (cr, childsUpds) <- initChilds newn v getst proc childs
      pure (cr >>= \_ => removeDomNode newn, attrsUpds ++ childsUpds)
  initTemplate' n v getst proc (TextNode attrs str) =
    do
      newn <- appendNode n "span"
      setText str newn
      attrUpds <- initAttributes v newn getst proc attrs
      pure (removeDomNode newn, attrUpds)
  initTemplate' n v getst proc (DynTextNode attrs getter) =
    do
      newn <- appendNode n "span"
      setText (getter v) newn
      attrsUpds <- initAttributes v newn getst proc attrs
      pure (removeDomNode newn, MkUpdate getter (\x,y => if x ==y then pure () else setText y newn) :: attrsUpds)
  initTemplate' n v getst proc (InputNode IText attrs) =
    do
      i <- appendNode n "input"
      setAttribute i ("type", "text")
      attrsUpds <- initAttributesInp v i getst proc id id attrs
      pure (removeDomNode i, attrsUpds)
  initTemplate' n v getst proc (FoldNode {a} {b} {s} {i} {r} s0 fupd t attrs) =
    do
      ctxS <- makeCtx s0
      ctxU <- makeCtx []
      (r, upds) <- initTemplate'
                n
                s0
                (getCtx ctxS)
                (updateFold {a=a} {b=b} {s=s} {i=i} ctxU ctxS fupd getst attrs proc)
                t
      setCtx ctxU upds
      pure (r, calcFoldUpdatesList ctxU ctxS attrs)
  initTemplate' n v getst proc (FormNode submit attrs childs) =
    do
      frm <- appendNode n "form"
      registEvent (procClick getst proc submit) frm "submit" preventDefault
      attrsUpds <- initAttributes v frm getst proc attrs
      (cr, childsUpds) <- initChilds frm v getst proc childs
      pure (cr >>= \_ => removeDomNode frm, attrsUpds ++ childsUpds)
  initTemplate' n v getst proc (ListTemplateNode tag attrs h t) =
    do
      newn <- appendNode n tag
      attrsUpds <- initAttributes v newn getst proc attrs
      upds <- addListTemplateNodes 0 newn getst proc h t (h v)
      ctxU <- makeCtx upds
      pure (getCtx ctxU >>= removeListNodes >>= \_ => removeDomNode newn
           , (MkUpdate id (updateLT newn getst proc h t ctxU)) :: attrsUpds)
  initTemplate' n v getst proc (ImgNode attrs x) =
    do
      nd <- appendNode n "img"
      setAttribute nd ("src", x)
      attrsUpds <- initAttributes v nd getst proc attrs
      pure (removeDomNode nd, attrsUpds)
  initTemplate' n v getst proc (ContraMapNode f t) =
    mapUpdates f <$> initTemplate' n (f v) (f <$> getst) proc t
  initTemplate' n v getst proc EmptyNode =
    pure (pure (), [])
  initTemplate' n v getst proc (CaseNode tag attrs f h templs) =
    do
      newn <- appendNode n tag
      attrsUpds <- initAttributes v newn getst proc attrs
      let (i**x) = h v
      ctxS <- makeCtx x
      (r, upds) <- initTemplate' newn x (getCtx ctxS) proc (templs i)
      ctxUpds <- makeCtx (i ** upds)
      ctxR <- makeCtx r
      pure ( (join $ getCtx ctxR) >>= \_=>removeDomNode newn
           , (updateCaseNode newn f h getst proc templs ctxR ctxUpds) :: attrsUpds)



export
initTemplate : DomNode -> a -> JS_IO a -> (b -> JS_IO ()) -> Template a b -> JS_IO (TemplateState a)
initTemplate n v getst proc t = pure $ MkTemplateState n v (snd !(initTemplate' n v getst proc t))

export
updateTemplate : a -> TemplateState a-> JS_IO (TemplateState a)
updateTemplate x (MkTemplateState n oldx upds) =
  do
    procUpdates oldx x upds
    pure (MkTemplateState n x upds)


---------- Primitives -------------
export
span : List (Attribute a f) -> List (Template a f) -> Template a f
span = CustomNode "span"

export
div : List (Attribute a f) -> List (Template a f) -> Template a f
div = CustomNode "div"

export
textinput : List (InputAttribute a f String) ->
              Template a f
textinput attrs = InputNode IText attrs


export
onchange : (a -> c -> b) ->
             InputAttribute  a b c
onchange = OnChange

export
onclick : (a -> b) -> Attribute a b
onclick = EventClick

export
dynsetval : (a -> Maybe y) -> InputAttribute a f y
dynsetval = DynSetVal

export
text : List (Attribute a f) -> String -> Template a f
text = TextNode

export
dyntext : List (Attribute a f) -> (a -> String) ->
              Template a f
dyntext = DynTextNode

export
form : (a -> b) -> List (Attribute a b) -> List (Template a b) -> Template a b
form = FormNode

export
foldTemplate : s -> (s->i->(s,Maybe r)) -> Template s i -> List (FoldAttribute a b s r) -> Template a b
foldTemplate = FoldNode

export
listOnDiv : List (Attribute a b) -> (a -> List c) -> Template c b -> Template a b
listOnDiv = ListTemplateNode "div"

export
img : List (Attribute a f) -> String -> Template a f
img = ImgNode

export
style : IGen s a (List Style) => s -> Attribute a f
style x = StrAttribute "style" (map styleStr $ getGen x)

export
customNode : String -> List (Attribute a f) -> List (Template a f) -> Template a f
customNode = CustomNode

infixl 4 >$<

export
(>$<) : (a->b) -> Template b c -> Template a c
(>$<) = ContraMapNode

export
emptyTemplate : Template a b
emptyTemplate = EmptyNode

export
caseTemplateSpan : DecEq i => List (Attribute a b) -> (f : i -> Type) ->  (a->DPair i f) ->
                          ((x:i) -> Template (f x) b) -> Template a b
caseTemplateSpan = CaseNode "span"