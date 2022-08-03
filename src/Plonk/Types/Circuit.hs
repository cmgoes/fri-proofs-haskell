module Plonk.Types.Circuit
  ( Circuit (..)
  , NumRows (..)
  , ColTypes (..)
  ) where


import Stark.Types.Scalar (Scalar)


data Circuit f =
  Circuit
  { numRows :: NumRows
  , colTypes :: ColTypes
  , degreeBound :: PolyDegreeBound
  , constraints :: Constraints
  , fixedValues :: FixedValues
  }


data ColTypes =
  ColTypes
  { numInstanceCols :: NumCols Instance
  , numAdviceCols :: NumCols Advice
  , numFixedCols :: NumCols Fixed
  }


newtype NumCols a = NumCols { unNumCols :: Int }

data Instance
data Advice
data Fixed


newtype NumRows = NumRows { unNumRows :: Int } 


newtype PolyDegreeBound = PolyDegreeBound { unDegreeBound :: Int }


newtype Constraints = Constraints { unConstraint :: [Constraint] }


newtype Constraint = Polynomial RelativeCellRef


data RelativeCellRef = RelativeCellRef RelativeRowIndex ColIndex


newtype Polynomial v = Polynomial { unPolynomial :: [Monomial v] }


data Monomial v = Monomial Scalar (Map v Exponent)


newtype Exponent = Exponent { unExponent :: Int }


newtype FixedValues = FixedValues { unFixedValues :: CellIndex -> Scalar }


data CellIndex = CellIndex RowIndex


newtype RowIndex = RowIndex { unRowIndex :: Int }


newtype RelativeRowIndex = RelativeRowIndex { unRelativeRowIndex :: Int }


newtype ColIndex = ColIndex { unColIndex :: Int }
