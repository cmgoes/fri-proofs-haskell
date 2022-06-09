{-# LANGUAGE GeneralizedNewtypeDeriving #-}


module Stark.Fri.Types
  ( Offset (Offset, unOffset)
  , Omega (Omega, unOmega)
  , DomainLength (DomainLength, unDomainLength)
  , ExpansionFactor (ExpansionFactor, unExpansionFactor)
  , NumColinearityTests (NumColinearityTests, unNumColinearityTests)
  , ListSize (ListSize, unListSize)
  , RandomSeed (RandomSeed, unRandomSeed)
  , ReducedListSize (ReducedListSize, unReducedListSize)
  , SampleSize (SampleSize, unSampleSize)
  , Index (Index, unIndex)
  , ReducedIndex (ReducedIndex, unReducedIndex)
  , Codeword (Codeword, unCodeword)
  , ProofStream (ProofStream, unProofStream)
  ) where


import Codec.Serialise (Serialise)
import Data.Bits (Bits)
import Data.ByteString (ByteString)

import Stark.Types.MerkleHash (MerkleHash)
import Stark.Types.Scalar (Scalar)


newtype Offset = Offset { unOffset :: Scalar }


newtype Omega = Omega { unOmega :: Scalar }


newtype DomainLength = DomainLength { unDomainLength :: Int }


newtype ExpansionFactor = ExpansionFactor { unExpansionFactor :: Rational }


newtype NumColinearityTests = NumColinearityTests { unNumColinearityTests :: Int }


newtype ListSize = ListSize { unListSize :: Int }


newtype RandomSeed = RandomSeed { unRandomSeed :: ByteString }


newtype ReducedListSize = ReducedListSize { unReducedListSize :: Int }


newtype SampleSize = SampleSize { unSampleSize :: Int }


newtype Index = Index { unIndex :: Int }
  deriving (Eq, Ord, Num, Enum, Real, Integral, Bits)


newtype ReducedIndex = ReducedIndex { unReducedIndex :: Int }
  deriving (Eq, Ord)


newtype Codeword = Codeword { unCodeword :: [MerkleHash] }
  deriving Serialise


newtype ProofStream = ProofStream { unProofStream :: [Codeword] }
  deriving Serialise