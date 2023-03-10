module Stark.UnivariatePolynomial
  ( degree,
    isZero,
    leadingCoefficient,
    evaluate,
    interpolate,
    constant,
    linear,
    areColinear,
    normalize,
  )
where

import Data.List (foldl')
import Data.Map
  ( elems,
    lookupMax,
    singleton,
  )
import qualified Data.Map as Map
import Math.Algebra.Polynomial.Class (Polynomial (evalP), Ring)
import Math.Algebra.Polynomial.FreeModule (FreeMod (FreeMod, unFreeMod))
import Math.Algebra.Polynomial.Univariate
  ( U (U),
    Univariate (Uni),
    unUni,
  )
import Stark.Types.Scalar (Scalar)
import qualified Stark.Types.Scalar as Scalar
import Stark.Types.UnivariatePolynomial (UnivariatePolynomial (UnivariatePolynomial, unUnivariatePolynomial))

degree :: Eq a => Num a => UnivariatePolynomial a -> Int
degree (UnivariatePolynomial p) =
  case lookupMax (Map.filter (/= 0) (unFreeMod (unUni p))) of
    Just (U i, _) -> i
    Nothing -> -1

isZero :: Eq a => Num a => UnivariatePolynomial a -> Bool
isZero = all (== 0) . elems . unFreeMod . unUni . unUnivariatePolynomial

leadingCoefficient :: UnivariatePolynomial a -> Maybe a
leadingCoefficient (UnivariatePolynomial p) = snd <$> lookupMax (unFreeMod (unUni p))

evaluate :: Ring a => UnivariatePolynomial a -> a -> a
evaluate (UnivariatePolynomial p) x = evalP id (const x) p

linear :: Scalar -> UnivariatePolynomial Scalar
linear coef = UnivariatePolynomial (Uni (FreeMod (singleton (U 1) coef)))

constant :: Scalar -> UnivariatePolynomial Scalar
constant coef = UnivariatePolynomial (Uni (FreeMod (singleton (U 0) coef)))

lagrangeBases :: [Scalar] -> [UnivariatePolynomial Scalar]
lagrangeBases xs =
  [ foldl'
      (*)
      1
      [ (linear 1 - constant xi) * constant (recip (xj - xi))
        | xi <- xs,
          xj /= xi
      ]
    | xj <- xs
  ]

interpolate :: [(Scalar, Scalar)] -> UnivariatePolynomial Scalar
interpolate ps =
  normalize $
    foldl'
      (+)
      0
      [ constant yj * lj
        | (yj, lj) <- zip (snd <$> ps) (lagrangeBases (fst <$> ps))
      ]

areColinear :: [(Scalar, Scalar)] -> Bool
areColinear = (< 2) . degree . normalize . interpolate

normalize :: UnivariatePolynomial Scalar -> UnivariatePolynomial Scalar
normalize (UnivariatePolynomial (Uni (FreeMod p))) =
  UnivariatePolynomial . Uni . FreeMod $ Scalar.normalize <$> p
