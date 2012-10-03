---------------------------------------------------------------------------
--   | Provides the "AsK3" type and instances for the K3 AST.

-- Header material                                                      {{{
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}

module Dyna.BackendK3.Render where

import           Control.Monad.State
import           Text.PrettyPrint.Free

import           Dyna.BackendK3.AST
import           Dyna.XXX.MonadUtils
import           Dyna.XXX.THTuple


------------------------------------------------------------------------}}}
-- Type handling                                                        {{{

    -- | Unlike AsK3 below, we don't need to thread a variable counter
    --   around since K3 doesn't have tyvars
newtype AsK3Ty e (a :: *) = AsK3Ty { unAsK3Ty :: Doc e }

instance K3Ty (AsK3Ty e) where
  tAnn (Ann anns) (AsK3Ty e) = AsK3Ty$ 
       parens e <> " @ "
    <> (encloseSep lbrace rbrace comma $ map text anns)

  tBool   = AsK3Ty$ "bool"
  tByte   = AsK3Ty$ "byte"
  tFloat  = AsK3Ty$ "float"
  tInt    = AsK3Ty$ "int"
  tString = AsK3Ty$ "string"
  tUnit   = AsK3Ty$ "unit"
  tUnk    = AsK3Ty$ "_"

  -- tPair (AsK3Ty ta) (AsK3Ty tb) = AsK3Ty$ tupled [ ta, tb ]

  tMaybe (AsK3Ty ta) = AsK3Ty$ "Maybe" <+> ta

  tColl CTSet  (AsK3Ty ta) = AsK3Ty$ braces   ta
  tColl CTBag  (AsK3Ty ta) = AsK3Ty$ encBag   ta
  tColl CTList (AsK3Ty ta) = AsK3Ty$ brackets ta

  tFun (AsK3Ty ta) (AsK3Ty tb) = AsK3Ty$ ta <+> "->" <+> tb

  tRef (AsK3Ty ta) = AsK3Ty$ "ref" <+> ta

    -- XXX TUPLES Note the similarities!
  tTuple2 us = AsK3Ty $ tupled $ tupleopEL unAsK3Ty us
  tTuple3 us = AsK3Ty $ tupled $ tupleopEL unAsK3Ty us
  tTuple4 us = AsK3Ty $ tupled $ tupleopEL unAsK3Ty us

------------------------------------------------------------------------}}}
-- Collection handling                                                  {{{

class K3CFn (c :: CKind) where
  k3cfn_empty :: AsK3 e (CTE c a)
  k3cfn_sing  :: AsK3 e vma -> AsK3 e (CTE c vma)

instance K3CFn CSet where
  k3cfn_empty = AsK3$ const$ "{ }"
  k3cfn_sing (AsK3 e) = AsK3$ braces . e

instance K3CFn CList where
  k3cfn_empty = AsK3$ const$ "[ ]"
  k3cfn_sing (AsK3 e) = AsK3$ brackets . e

instance K3CFn CBag where
  k3cfn_empty = AsK3$ const$ "{| |}"
  k3cfn_sing (AsK3 e) = AsK3$ encBag . e

------------------------------------------------------------------------}}}
-- Pattern handling                                                     {{{

class (Pat w) => K3PFn w where
  k3pfn :: Bool -> PatDa w -> State Int (Doc e, PatReprFn w (AsK3 e))

instance (K3BaseTy a) => K3PFn (PKVar (a :: *)) where
  k3pfn _ (PVar tr) = do
    n <- incState
    let sn = text $ "x" ++ show n
    return (sn <> colon <> unAsK3Ty (unUTR tr)
           ,AsK3$ const$ sn)

instance (K3PFn w) => K3PFn (PKJust w) where
  k3pfn _ (PJust w) = do
    (p, r) <- k3pfn False w
    return ("just " <> parens p, r)

  -- XXX TUPLES this should be automatically generated
instance (K3PFn wa, K3PFn wb)
         => K3PFn (PKTuple2 '(wa,wb))
 where
  k3pfn _ (PTuple2 wa wb) = do
    (ba, ra) <- k3pfn False wa
    (bb, rb) <- k3pfn False wb
    return (tupled [ ba, bb ], (ra,rb))

instance (K3PFn wa, K3PFn wb, K3PFn wc)
         => K3PFn (PKTuple3 '(wa,wb,wc))
 where
  k3pfn _ (PTuple3 wa wb wc) = do
    (ba, ra) <- k3pfn False wa
    (bb, rb) <- k3pfn False wb
    (bc, rc) <- k3pfn False wc
    return (tupled [ ba, bb, bc ], (ra,rb,rc))

instance (K3PFn wa, K3PFn wb, K3PFn wc, K3PFn wd)
         => K3PFn (PKTuple4 '(wa,wb,wc,wd))
 where
  k3pfn _ (PTuple4 wa wb wc wd) = do
    (ba, ra) <- k3pfn False wa
    (bb, rb) <- k3pfn False wb
    (bc, rc) <- k3pfn False wc
    (bd, rd) <- k3pfn False wd
    return (tupled [ ba, bb, bc, bd ], (ra,rb,rc,rd))

{-
instance K3PFn (PKTup '[]) where
  k3pfn n _ PTupN = (n, rparen, AsK3$const$rparen)

instance (Pat (PKTup as), K3PFn (PKTup as), K3PFn a) 
      => K3PFn (PKTup (a ': as)) where
  k3pfn n b (PTupC a as) = let (n', pa, ra)  = k3pfn n  False a
                               (n'', ps, rs) = k3pfn n' True  as
                           in (n'', extend pa ps, (ra,rs))
    where
      left           = if b then comma else lparen
      extend   pa ps = left <> pa <> ps
-}

------------------------------------------------------------------------}}}
-- Slice handling                                                       {{{

class (Slice (AsK3 e) w) => K3SFn e w where
  k3sfn :: Bool -> SliceDa w -> AsK3 e (SliceTy w)

instance (K3BaseTy a) => K3SFn e (SKVar (AsK3 e) (a :: *)) where
  k3sfn _ (SVar r) = r

instance (K3BaseTy a) => K3SFn e (SKUnk (a :: *)) where
  k3sfn _ SUnk = AsK3$ const$ text "_"

instance (K3SFn e s) => K3SFn e (SKJust s) where
  k3sfn _ (SJust s) = AsK3$ \n -> "Just" <> parens (unAsK3 (k3sfn False s) n)

  -- XXX TUPLES this should be automatically generated
instance (K3SFn e sa, K3SFn e sb)
         => K3SFn e (SKTuple2 '(sa,sb))
 where
  k3sfn _ (STuple2 sa sb) =
    AsK3$ \n -> tupled [ unAsK3 (k3sfn False sa) n
                       , unAsK3 (k3sfn False sb) n ]

instance (K3SFn e sa, K3SFn e sb, K3SFn e sc)
         => K3SFn e (SKTuple3 '(sa,sb,sc))
 where
  k3sfn _ (STuple3 sa sb sc) =
    AsK3$ \n -> tupled [ unAsK3 (k3sfn False sa) n
                       , unAsK3 (k3sfn False sb) n
                       , unAsK3 (k3sfn False sc) n ]

{-
instance K3SFn e (SKTup '[]) where
  k3sfn _ STupN = AsK3$const$rparen

instance (Slice (AsK3 e) (SKTup as), K3SFn e (SKTup as), K3SFn e a) 
      => K3SFn e (SKTup (a ': as)) where
  k3sfn b (STupC a as) = AsK3$ \n -> left <> unAsK3 (k3sfn False a) n
                                          <> unAsK3 (k3sfn True as) n
    where
      left           = if b then comma else lparen
-}

------------------------------------------------------------------------}}}
-- Expression handling                                                  {{{

newtype AsK3 e (a :: *) = AsK3 { unAsK3 :: Int -> Doc e }

instance K3 (AsK3 e) where
  type K3AST_Coll_C (AsK3 e) c = K3CFn c
  type K3AST_Pat_C (AsK3 e) p = K3PFn p
  type K3AST_Slice_C (AsK3 e) s = K3SFn e s

  cAnn (Ann anns) (AsK3 e) = AsK3$ \n ->
       parens (e n) <> " @ "
    <> (encloseSep lbrace rbrace comma $ map text anns)

  cComment str (AsK3 a) = AsK3$ \n -> "\n// " <> text str <> "\n" <> a n

  cBool   n      = AsK3$ const$ text$ show n
  cByte   n      = AsK3$ const$ text$ show n
  cFloat  n      = AsK3$ const$ text$ show n
  cInt    n      = AsK3$ const$ text$ show n
  cString n      = AsK3$ const$ text$ show n
  cNothing       = AsK3$ const$ "nothing"
  cUnit          = AsK3$ const$ "unit"

  eVar (Var v) _ = AsK3$ const$ text v


  eJust (AsK3 a)          = builtin "Just " [ a ]
  -- ePair (AsK3 a) (AsK3 b) = AsK3$ \n -> tupled [a n, b n]

    -- XXX TUPLES Note the similarity of these!
  eTuple2 t = AsK3 $ \n -> tupled $ tupleopEL (flip unAsK3 n) t
  eTuple3 t = AsK3 $ \n -> tupled $ tupleopEL (flip unAsK3 n) t
  eTuple4 t = AsK3 $ \n -> tupled $ tupleopEL (flip unAsK3 n) t

  eEmpty = k3cfn_empty
  eSing  = k3cfn_sing
  eCombine (AsK3 a) (AsK3 b) = AsK3$ \n -> parens (a n) <> " ++ " <> parens (b n)
  eRange (AsK3 f) (AsK3 l) (AsK3 s) = builtin "range" [ f, l, s ]
  
  eAdd = binop "+"
  eMul = binop "*"
  eNeg (AsK3 b) = AsK3$ \n -> "-" <> parens (b n)

  eEq  = binop "=="
  eLt  = binop "<"
  eLeq = binop "<="
  eNeq = binop "!="

  eLam w f = AsK3$ \n -> let ((pat, arg),n') = runState (k3pfn False w) n
                         in align ("\\" <> pat <+> "->" `above` unAsK3 (f arg) n')

  eApp (AsK3 f) (AsK3 x) = AsK3$ \n ->
    parens (parens (f n) `aboveBreak` parens (x n))

  eBlock ss (AsK3 r) = AsK3$ \n -> 
    "do" <> (semiBraces (map ($ n) ((map unAsK3 ss) ++ [r])))

  eIter (AsK3 f) (AsK3 c) = builtin "iterate" [ f, c ]

  eITE (AsK3 b) (AsK3 t) (AsK3 e) = AsK3$ \n ->
    "if" <+> (align $ above (parens (b n))
                            ("then" <+> parens (t n) `aboveBreak`
                             "else"  <+> parens (e n)))

  eMap     (AsK3 f) (AsK3 c)                   = builtin "map"       [ f, c    ]
  eFiltMap (AsK3 f) (AsK3 m) (AsK3 c)          = builtin "filtermap" [ f, m, c ]
  eFlatten (AsK3 c)                            = builtin "flatten"   [ c ]
  eFold    (AsK3 f) (AsK3 z) (AsK3 c)          = builtin "fold"      [ f, z, c ]
  eGBA     (AsK3 p) (AsK3 f) (AsK3 z) (AsK3 c) = builtin "groupby"   [ p, f, z, c ]
  eSort    (AsK3 c) (AsK3 f)                   = builtin "sort"      [ c, f ]
  ePeek    (AsK3 c)                            = builtin "peek"      [ c ]

  eSlice w (AsK3 c) = AsK3$ \n -> c n <> brackets (unAsK3 (k3sfn False w) n)

  eInsert (AsK3 c) (AsK3 e)          = builtin "insert" [ c, e ]
  eDelete (AsK3 c) (AsK3 e)          = builtin "delete" [ c, e ]
  eUpdate (AsK3 c) (AsK3 o) (AsK3 n) = builtin "update" [ c, o, n ]

  eAssign          = binop "<-" 
  eDeref  (AsK3 r) = builtin "deref" [ r ]
    -- XXX that doesn't seem to actually be right!
   

------------------------------------------------------------------------}}}
-- Miscellany                                                           {{{

encBag :: Doc e -> Doc e
encBag = enclose "{|" "|}"

    -- Overly polymorphic; use only when correct!
binop :: Doc e -> AsK3 e a -> AsK3 e b -> AsK3 e c
binop o (AsK3 a) (AsK3 b) = AsK3$ \n ->     parens (align $ a n)
                                        </> o
                                        </> parens (align $ b n)

    -- Overly polymorphic; use only when correct!
builtin :: Doc e -> [ Int -> Doc e ] -> AsK3 e b
builtin fn as = AsK3$ \n -> fn <> tupled (map ($ n) as)

instance Show (AsK3 e a) where
  show (AsK3 f) = show $ f 0

sh :: AsK3 e a -> Doc e
sh (AsK3 f) = f 0

instance Show (AsK3Ty e a) where
  show (AsK3Ty f) = show f

sht :: AsK3Ty e a -> String
sht = show

shd :: Decl (AsK3Ty e) (AsK3 e) t -> Doc e
shd (Decl (Var name) tipe body) =
     "declare "
  <> text name
  <> space <> colon <> space
  <> unAsK3Ty tipe
  <> case body of
       Nothing -> empty
       Just b  -> space <> equals <> space <> unAsK3 b 0
  <> semi

------------------------------------------------------------------------}}}
