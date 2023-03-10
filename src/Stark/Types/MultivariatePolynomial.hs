module Stark.Types.MultivariatePolynomial (MultivariatePolynomial) where

import Data.Kind (Type)
import Math.Algebra.Polynomial.Multivariate.Generic (Poly)
import Stark.Types.Scalar (Scalar)

type MultivariatePolynomial :: Type -> Type
type MultivariatePolynomial v = Poly Scalar v
