---------------------------------------------------------------------------
-- | Reimplementation of the Mercury mode system (Inst)
--
-- This module contains the definitions of instantiation states and the
-- primitive predicates on insts.  For clarity and flexibility of
-- implementation, many of these primitive predicates are parameterized on
-- some 'Monad' and defined in terms of open recursion.  This leaves it to
-- the outer 'Monad' to deal with (or not, if termination isn't important ;)
-- ) a lot of technicalities that would obscure the exposition of the
-- thesis' material.

-- Header material                                                      {{{
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -Wall #-}
module Dyna.Analysis.Mode.Inst(
  InstF(..),
  iNotReached, iIsNotReached,
  iUniq, iWellFormed_, iEq_, iGround_,
  iLeq_, iLeqGLB_,
  iSub_, iSubGLB_, iSubLUB_,
) where

-- import           Control.Monad
import qualified Data.Foldable            as F
import qualified Data.Traversable         as T
import qualified Data.Map                 as M
-- import qualified Data.Set                 as S
import           Dyna.XXX.DataUtils
import           Dyna.XXX.MonadUtils

import           Dyna.Analysis.Mode.Uniq

------------------------------------------------------------------------}}}
-- Instantiation States                                                 {{{

-- | Instantiation states, parametric in Prolog functor @f@ with open
-- recursion through @i@.
--
-- We differ from the thesis and the mercury implementation (see prose, p60,
-- \"Obviously, it is not...\") in the use of open recursion rather than a
-- @defined_inst@ branch in the @InstF@.  Rather, we use a disjunctive @i@.
-- Similarly, we use our disjunctive @i@ rather than a separate @alias@
-- constructor (see figure 5.3, p94).
--
-- It's also worth pointing out, while here, that the mode system is
-- concerned only with actual data, not types.  There is clearly some
-- overlap with a type system, and we may wish to investigate adding typing
-- information to this system rather than brew an entirely separate type
-- system (XXX).  In particular, the importance here is that 'IBound' and
-- 'IUniv' should be viewed as intersected with the type information, if
-- any.
--
-- Based on figure 5.3, p94 (but see figure 3.17, p50, for easier cases)
--
-- The 'Ord' instance is solely for internal use; for reasoning, use lattice
-- functions.
data InstF f i = 
  -- | An unbound inst.
  --
  -- If you like a machine-core representation-centric view of
  -- the universe, such a thing is a pointer whose own space has
  -- been allocated already but is not pointing to anything yet.
  -- Rules which bind free variables engage in allocation and
  -- fill in these holes.
    IFree

  -- | A possibly-bound inst.  We have lost track of whether or
  -- not the given variable is free.  We may not pass such a
  -- thing to a predicate expecting a bound variable, and any
  -- predicate expecting a free variable must be prepared to
  -- check and engage in unification, rather than allocation,
  -- with the possible (partial) structure bound here.
  --
  -- Note that we are saying nothing about the possible data
  -- bound by this variable; that would be the job of the type
  -- system.
  | IAny   !Uniq

  -- | A bound inst.  More specifically, a disjunction of
  -- possible binding states: it's guaranteed to be one of these
  -- functors and its associated insts.
  --
  -- Note that defition 3.2.11 (p50) requires that the
  -- uniqueness of the inner Insts be below by <=
  -- (see the 'iWellformed' predicate below)
  --
  -- The Bool field, which is an extension from the thesis,
  -- indicates the possibility that this inst is
  -- bound to a base-case of the term universe.
  --
  -- XXX It's possible that we would want a @[TBaseSkolem]@
  -- field for tracking which base-cases, or even a @[TBase]@
  -- field for recording possible actual base-cases, too,
  -- but one thing at a time.
  --
  -- Definition 3.2.18, p52:
  -- @not_reached(u) === IBound u M.empty False@.
  -- @not_reached    === not_reached(UUnique)@.
  | IBound !Uniq
           !(M.Map f [i])
           !Bool

  -- | This one is not in the thesis exposition but is used during
  -- computation to represent the entire universe of ground
  -- terms.  See prose, p63, \"For efficiency, we treat ground...\".
  --
  -- Defninition 3.2.17, p52 is thus rewritten:
  -- @ground(u) === IUniv u@.
  | IUniv  !Uniq

  -- XXX Mercury has a concept of \"higher-order modes\", which we
  -- do not yet support (though there is grumbling about it in
  -- the background).  See 3.2.4 p55 et seq.

 deriving (Eq, F.Foldable, Functor, Ord, Show, T.Traversable)

------------------------------------------------------------------------}}}
-- Instantiation States: Unary predicates                               {{{

{-
-- | Test if a term is in the set generated by the inst concretization
-- function.
--
-- Use as @term `inIGamma` inst@.
--
-- Surrogate for definition 3.2.12, p51
inIGamma :: RA (UTerm (RTerm f) v) -> Inst f -> Bool
inIGamma _        IFree          = True
inIGamma _        IBoundUniverse = True
inIGamma (RA r _) (IAny u)       = r == uniqGamma u
inIGamma (RA r t) (IBound u ts)  = r == uniqGamma u
                                   && undefined -- XXX
-}

-- | Extract the uniqueness from an inst.
--
-- Based on definition 3.2.13, p51 but see prose, p51, \"Note that there is
-- no uniqueness annotation on the free inst\" -- we choose to make that
-- explicit here.
iUniq :: InstF f i -> Uniq
iUniq IFree          = UUnique
iUniq (IAny u)       = u
iUniq (IBound u _ _) = u
iUniq (IUniv u)      = u
{-# INLINE iUniq #-}

-- | Check that an instantiation state is well-formed as per defintion
-- 3.2.11, p50.
iWellFormed_ :: (Monad m)
             => (Uniq -> i -> m Bool)
             ->  Uniq -> InstF f i
             -> m Bool
iWellFormed_ _ _  IFree          = return True
iWellFormed_ _ u' (IAny u)       = return $ u <= u'
iWellFormed_ q u' (IBound u b _) = if u <= u'
                                    then mfmamm (q u) b
                                    else return False
iWellFormed_ _ u' (IUniv u)      = return $ u <= u'
-- iWellFormed_ _ u' (INotReached u) = return $ u <= u'
{-# INLINE iWellFormed_ #-}

-- | Is an instantiation ground?
--
-- Surrogate for definition 3.2.17, p52
iGround_ :: (Monad m) => (i -> m Bool) -> InstF f i -> m Bool
iGround_ q (IBound UUnique b _) = mfmamm q b
iGround_ _ (IUniv _) = return True
iGround_ _ _ = return False

------------------------------------------------------------------------}}}
-- Instantiation States: Binary predicates                              {{{

-- | Equality of two insts
iEq_ :: (Ord f, Monad m)
     => (i -> i -> m Bool)
     -> InstF f i -> InstF f i -> m Bool
iEq_ _ IFree IFree = return $ True
iEq_ _ _     IFree = return $ False
iEq_ _ IFree _     = return $ False

iEq_ _ (IAny u) (IAny v) | u == v = return True
iEq_ _ _        (IAny _)          = return False
iEq_ _ (IAny _) _                 = return False

iEq_ _ (IUniv u) (IUniv v) | u == v = return True
iEq_ _ _         (IUniv _)          = return False
iEq_ _ (IUniv _) _                  = return False

iEq_ q (IBound u b c) (IBound u' b' c')
  | u == u' && c == c' && (M.null $ M.difference b' b) =
  flip mapForallM b $
     \f is -> case M.lookup f b' of
                Nothing  -> return False
                Just is' -> allM $ zipWith q is is'
iEq_ _ (IBound _ _ _) (IBound _ _ _)
  | otherwise = return False

-- | Instantiatedness partial order with uniqueness (≼)
--
-- The purpose of iLeq is two-fold:
--   1. To describe the allowable transitions during forward execution
--      of some predicate.  (prose, p32, \"A major rôle...\").
--      Specifically, a binding may move from @i'@ to @i@ if @i `iLeq` i'@.
--   2. Defining the abstract unification lattice; see definitions
--      3.1.18 (p38), 3.2.2 (p44), 3.2.6 (p46), 3.2.19 (p53), and
--      5.3.8 (p98).
--
-- IAny `iLeq` IAny is declared (prose, p46, \"We allow...\") to be unsafe
-- in general but safe for reasoning about forward execution (recall defn
-- 3.1.10, p34).  XXX I do not understand.
--
-- Definition 3.2.14, p51 (see also definitions 3.1.4 (p32) and 3.2.5 (p46))
iLeq_ :: (Ord f, Monad m)
      => (i -> InstF f i -> m Bool)
      -> (i -> i -> m Bool)
      -> InstF f i -> InstF f i -> m Bool
iLeq_ _ _  _            IFree             = return $ True
iLeq_ _ _ IFree        _                  = return $ False
iLeq_ _ _ (IAny u)     (IAny u')          = return $ u' <= u
iLeq_ _ _ (IAny _)     _                  = return $ False
iLeq_ _ _ (IUniv u)    (IAny u')          = return $ u' <= u
iLeq_ _ _ (IUniv u)    (IUniv u')         = return $ u' <= u
iLeq_ _ _ (IUniv _)    _                  = return $ False
iLeq_ q _ (IBound u b _) r@(IAny u')      = andM1 (u' <= u) $
    mfmamm (flip q r) b
iLeq_ q _ (IBound u b _) r@(IUniv u')     = andM1 (u' <= u) $
    mfmamm (flip q r) b
iLeq_ _ q (IBound u m b) (IBound u' m' b') = andM1 (b <= b' && u' <= u) $
    flip mapForallM m $
      \f is -> case M.lookup f m' of
                 Nothing -> return False
                 Just is' -> allM $ zipWithTails q crf crf is is'
    -- XXX Ought to assert that length is == length is'
{-
iLeq_ _ (INotReached u) (IAny u')        = return $ u' <= u
iLeq_ _ (INotReached u) (IUniv u')       = return $ u' <= u
iLeq_ _ (INotReached u) (INotReached u') = return $ u' <= u
-}
{-# INLINE iLeq_ #-}


-- | Compute the GLB under iLeq_ (⋏)
--
-- Since iLeq (≼) is a lattice, this is a total function.
iLeqGLB_ :: (Monad m, Ord f)
         => (i -> i -> m i)
         -> InstF f i
         -> InstF f i
         -> m (InstF f i)
iLeqGLB_ _ IFree      x            = return x
iLeqGLB_ _ x          IFree        = return x

iLeqGLB_ _ (IAny u)   (IAny u')    = return $ IAny (max u u')

iLeqGLB_ _ (IAny u')  (IUniv u)    = return $ IUniv (max u u')
iLeqGLB_ _ (IUniv u)  (IAny u')    = return $ IUniv (max u u')
iLeqGLB_ _ (IUniv u)  (IUniv u')   = return $ IUniv (max u u')

iLeqGLB_ _ (IBound u m b) (IAny u') = return $ IBound (max u u') m b
iLeqGLB_ _ (IAny u') (IBound u m b) = return $ IBound (max u u') m b

iLeqGLB_ _ (IBound u m b) (IUniv u') = return $ IBound (max u u') m b
iLeqGLB_ _ (IUniv u') (IBound u m b) = return $ IBound (max u u') m b

iLeqGLB_ q (IBound u m b) (IBound u' m' b') = do
    m'' <- mergeBoundLB q m m'
    return $! IBound (max u u') m'' (b && b')


-- iLeqGLB_ _ a@(INotReached _) _     = return $ Just a
-- iLeqGLB_ _ _ a@(INotReached _)     = return $ Just a

-- | Matches partial order with uniqueness (⊑)
--
-- Matching specifies the intersubstitutability of insts: if @i `iSub` i'@
-- then we may use anything with binding @i@ wherever the predicate would
-- require @i'@.
--
-- Note that this is not a full lattice.
--
-- Definition 3.2.15, p51 (see also definitions 3.1.11 (p35) and 3.2.7
-- (p46))
iSub_ :: (Ord f, Monad m)
      => (i -> InstF f i -> m Bool)
      -> (i -> i -> m Bool)
      -> InstF f i
      -> InstF f i
      -> m Bool
iSub_ _ _ IFree          IFree          = return $ True
-- iSub_ _ (INotReached _) IFree         = return $ True
iSub_ _ _ x@(IBound _ _ _) IFree | iIsNotReached x = return $ True
iSub_ _ _ IFree          _              = return $ False
iSub_ _ _ _              IFree          = return $ False
iSub_ _ _ (IAny u)       (IAny u')      = return $ u <= u'
iSub_ _ _ (IAny _)       _              = return $ False
iSub_ _ _ (IUniv u)      (IAny u')      = return $ u <= u'
iSub_ _ _ (IUniv u)      (IUniv u')     = return $ u <= u'
iSub_ _ _ (IUniv _)      _              = return $ False
iSub_ q _ (IBound u b _) r@(IAny u')    = andM1 (u <= u') $
    mfmamm (flip q r) b
iSub_ q _ (IBound u b _) r@(IUniv u')   = andM1 (u <= u') $
    mfmamm (flip q r) b
iSub_ _ q (IBound u m b) (IBound u' m' b') = andM1 (u <= u' && b <= b') $
    flip mapForallM m $
      \f is -> case M.lookup f m' of
                 Nothing -> return False
                 Just is' -> allM $ zipWithTails q crf crf is is'
    -- XXX Ought to assert that length is == length is'
-- iSub_ _ (INotReached u) (IAny u')     = return $ u <= u'
-- iSub_ _ (INotReached u) (IUniv u')    = return $ u <= u'
-- iSub_ _ _               _             = return $ False

-- | Compute the GLB under iSub_ (⊓)
iSubGLB_ :: (Ord f, Monad m)
         => (i -> i -> m i)
         -> InstF f i -> InstF f i -> m (InstF f i)
iSubGLB_ _ IFree      IFree        = return $ IFree
iSubGLB_ _ IFree      b            = return $ iNotReached (iUniq b)
iSubGLB_ _ a          IFree        = return $ iNotReached (iUniq a)

iSubGLB_ _ (IAny u)   (IAny u')    = return $ IAny (min u u')

iSubGLB_ _ (IAny u')  (IUniv u)    = return $ IUniv (min u u')
iSubGLB_ _ (IUniv u)  (IAny u')    = return $ IUniv (min u u')
iSubGLB_ _ (IUniv u)  (IUniv u')   = return $ IUniv (min u u')

iSubGLB_ _ (IBound u m b) (IAny u') = return $ IBound (min u u') m b
iSubGLB_ _ (IAny u') (IBound u m b) = return $ IBound (min u u') m b

iSubGLB_ _ (IBound u m b) (IUniv u') = return $ IBound (min u u') m b
iSubGLB_ _ (IUniv u') (IBound u m b) = return $ IBound (min u u') m b

iSubGLB_ q (IBound u m b) (IBound u' m' b') = do
    let u'' = min u u'
    -- NOTE: I was briefly concerned that we would have to pass u'' down
    -- through q, but since the well-formedness criteria may be assumed to
    -- hold for both m and m' (that is, for all insts contained in m (resp.
    -- m'), their uniqueness is <= u (resp. u')), and our recursion is
    -- defined by minimizing uniqueness, the uniqueness of the return is
    -- guaranteed to be <= min {u, u'} with no additional effort on our
    -- part.
    m'' <- mergeBoundLB q m m'
    return $ IBound u'' m'' (b && b')

-- iSubGLB_ _ a@(INotReached _) _     = return $ Just a
-- iSubGLB_ _ _ a@(INotReached _)     = return $ Just a
-- iSubGLB_ _ _         _             = return $ Nothing

-- | Compute the LUB under iSub_ (⊔)
--
-- Since 'iSub_' is not a full lattice, this is a partial function (thus
-- 'Maybe').  Note, however, that the recursion is defined to be total --
-- thus it is the responsibility of the outer 'Monad' to bail out if any
-- call to 'iSubGLB_' yields 'Nothing'.
iSubLUB_ :: (Ord f, Monad m)
         => (i -> i -> m i)
         -> InstF f i -> InstF f i -> m (Maybe (InstF f i))
iSubLUB_ _ IFree      IFree        = return $ Just IFree
iSubLUB_ _ IFree      b     | iIsNotReached b = return $ Just IFree
iSubLUB_ _ a          IFree | iIsNotReached a = return $ Just IFree
iSubLUB_ _ IFree      _            = return $ Nothing
iSubLUB_ _ _          IFree        = return $ Nothing

iSubLUB_ _ (IAny u)   (IAny u')    = return $ Just $ IAny  (max u u')
iSubLUB_ _ (IAny u')  (IUniv u)    = return $ Just $ IAny  (max u u')
iSubLUB_ _ (IUniv u)  (IAny u')    = return $ Just $ IAny  (max u u')
iSubLUB_ _ (IUniv u)  (IUniv u')   = return $ Just $ IUniv (max u u')

iSubLUB_ _ (IBound u _ _) (IAny u') = return $ Just $ IAny (max u u')
iSubLUB_ _ (IAny u') (IBound u _ _) = return $ Just $ IAny (max u u')

iSubLUB_ _ (IBound u _ _) (IUniv u') = return $ Just $ IUniv (max u u')
iSubLUB_ _ (IUniv u') (IBound u _ _) = return $ Just $ IUniv (max u u')

iSubLUB_ q (IBound u m b) (IBound u' m' b') = do
    m'' <- mergeBoundUB q m m'
    return $! Just $! IBound (max u u') m'' (b || b')

------------------------------------------------------------------------}}}
-- Instantiation States: Utility Functions                              {{{

-- | The bottom of the 'iLeq' lattice and 'iSub' semi-lattice, representing
-- the empty set of (non-ground) terms.
iNotReached :: Uniq -> InstF f i
iNotReached u = IBound u M.empty False

-- | Indicator function for 'iNotReached'
iIsNotReached :: InstF f i -> Bool
iIsNotReached (IBound _ m False) = M.null m
iIsNotReached _                  = False

crf :: (Monad m) => a -> m Bool
crf = const $ return False

-- | A common pattern we encounter in unary predicates, so let's just pull
-- it out.
mfmamm :: Monad m => (a -> m Bool) -> M.Map k [a] -> m Bool
mfmamm f = mapForallM (\_ -> allM . map f)

-- | Compute the lower bound of two guts of IBound constructors.
mergeBoundLB :: (Monad m, Ord f)
             => (i -> i -> m a)
             -> M.Map f [i] -> M.Map f [i] -> m (M.Map f [a])
mergeBoundLB q lm rm = T.sequence $ M.intersectionWith (\a b -> sequence $ zipWith q a b) lm rm

-- | Compute the upper bound of two guts of IBound constructors.
mergeBoundUB :: (Monad m, Ord f)
             => (i -> i -> m i)
             -> M.Map f [i] -> M.Map f [i] -> m (M.Map f [i])
mergeBoundUB q lm rm = T.sequence
                       $ M.mergeWithKey (\_ a b -> Just $ sequence $ zipWith q a b)
                                        (fmap return) (fmap return)
                                        lm rm

------------------------------------------------------------------------}}}
