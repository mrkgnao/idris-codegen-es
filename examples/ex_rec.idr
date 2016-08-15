module Main

import Js.Browser
import Data.Vect

data TstExp = Pos Nat
            | Neg Nat
            | Plus TstExp TstExp

Typeable TstExp where
  getTypeRep = %runElab deriveTypeable

Show TstExp where
  show (Pos x) = show x
  show (Neg x) = "(-" ++ show x ++ ")"
  show (Plus x y) = "(" ++ show x ++ " + " ++ show y ++ ")"


indentV : Nat -> View a -> View a
indentV i x = d $ t (pack $ the (List Char) $ replicate i '-') ++ x

indentF : Nat -> Form a -> Form a
indentF i = vtrans (indentV i)

tstForm : Nat -> Lazy (Form TstExp)
tstForm i =
  indentF i $ formBind
    (selectForm ["Pos", "Neg", "Plus"])
    f
    theForm
    cons
    getK
  where
    f : Fin 3 -> Type
    f FZ = Nat
    f (FS FZ) = Nat
    f _ = (TstExp, TstExp)
    theForm : (i: Fin 3) -> Form (f i)
    theForm FZ = natForm
    theForm (FS FZ) = natForm
    theForm (FS (FS FZ)) = tupleForm (tstForm $ i+1) (tstForm $ i+1)
    cons FZ x = Pos x
    cons (FS FZ) x = Neg x
    cons (FS (FS FZ)) (x,y) = Plus x y
    getK (Pos x) = (0 ** x)
    getK (Neg x) = (1 ** x)
    getK (Plus x y) = (2 ** (x,y))

vw : TstExp -> View TstExp
vw x = d $ (buildForm (Just $ FormSetVal x) $ addSubmit "Submit" $ tstForm 0)
           ++ d (t $ show x)


page : SimpleApp TstExp TstExp
page = MkSimpleApp
        (Pos 6)
        never
        vw
        (\x, y => (y, never))

main : JS_IO ()
main = do
  runApp page
