module Stark.UnivariatePolynomial
  ( degree
  , isZero
  , leadingCoefficient
  , evaluate
  , interpolate
  , constant
  , linear
  ) where


import Control.Arrow ((***))
import Data.Map (lookupMax, singleton)
import Math.Algebra.Polynomial.Class (Polynomial (evalP))
import Math.Algebra.Polynomial.FreeModule (FreeMod (FreeMod, unFreeMod))
import Math.Algebra.Polynomial.Univariate (Univariate (Uni), unUni, U (U), fromQUni)
import Math.Algebra.Polynomial.Univariate.Lagrange (lagrangeInterp)
import qualified Data.FiniteField.PrimeField as PrimeField

import Stark.Types.Scalar (Scalar (unScalar))
import Stark.Types.UnivariatePolynomial (UnivariatePolynomial)


degree :: UnivariatePolynomial -> Int
degree p =
  case lookupMax (unFreeMod (unUni p)) of
    Just (U i, _) -> i
    Nothing -> -1


isZero :: UnivariatePolynomial -> Bool
isZero = (== Nothing) . lookupMax . unFreeMod . unUni


leadingCoefficient :: UnivariatePolynomial -> Maybe Scalar
leadingCoefficient p = snd <$> lookupMax (unFreeMod (unUni p))


evaluate :: UnivariatePolynomial -> Scalar -> Scalar
evaluate p x = evalP id (const x) p


linear :: Scalar -> UnivariatePolynomial
linear coef = Uni (FreeMod (singleton (U 1) coef))


constant :: Scalar -> UnivariatePolynomial
constant coef = Uni (FreeMod (singleton (U 0) coef))


interpolate :: [(Scalar, Scalar)] -> UnivariatePolynomial
interpolate f = fromQUni $ lagrangeInterp ((g *** g) <$> f)
  where
    g :: Scalar -> Rational
    g = fromIntegral . PrimeField.toInteger . unScalar
--  let n = length f in
--  sum [constant yi *
--       (product [  (linear 1 - constant xj) / (constant (xi - xj))
--                 | (xj,yj) <- f, xj /= xi ])
--    | (xi,yi) <- f ]
