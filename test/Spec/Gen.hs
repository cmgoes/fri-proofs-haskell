{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE ScopedTypeVariables #-}


module Spec.Gen
  ( genFriConfiguration
  , defaultFriConfiguration
  , genProofStream
  , genCodeword
  , genQuery
  , genAuthPath
  , genCommitment
  , genCapCommitment
  , genByteString
  , genScalar
  , genLowDegreePoly
  , genBinaryTree
  ) where


import           Control.Lens                       ((^.))
import           Control.Monad                      (replicateM)
import           Data.ByteString                    (ByteString)
import qualified Data.ByteString                    as BS
import           Data.Generics.Labels               ()
import qualified Data.Map                           as Map
import           Data.Maybe                         (fromMaybe)
import           Math.Algebra.Polynomial.FreeModule (FreeMod (FreeMod))
import           Math.Algebra.Polynomial.Univariate (U (U), Univariate (Uni))

import Hedgehog (Gen)
import Hedgehog.Gen (choice, list)
import qualified Hedgehog.Range as Range
import qualified Stark.BinaryTree                   as BinaryTree
import           Stark.FiniteField                  (cardinality, generator,
                                                     primitiveNthRoot)
import           Stark.Fri                          (getMaxDegree)
import           Stark.Fri.Types                    (A (A), AuthPaths (AuthPaths),
                                                     B (B), C (C),
                                                     Codeword (Codeword),
                                                     DomainLength (DomainLength),
                                                     ExpansionFactor (ExpansionFactor),
                                                     FriConfiguration (FriConfiguration),
                                                     NumColinearityTests (NumColinearityTests),
                                                     Offset (Offset), Omega (Omega),
                                                     ProofStream (ProofStream),
                                                     Query (Query))
import           Stark.Types.AuthPath               (AuthPath (AuthPath))
import           Stark.Types.BinaryTree             (BinaryTree)
import           Stark.Types.CapCommitment          (CapCommitment (CapCommitment))
import           Stark.Types.CapLength              (CapLength (CapLength))
import           Stark.Types.Commitment             (Commitment (Commitment))
import           Stark.Types.MerkleHash             (MerkleHash (MerkleHash))
import           Stark.Types.Scalar                 (Scalar (Scalar))
import           Stark.Types.UnivariatePolynomial   (UnivariatePolynomial (UnivariatePolynomial))


genFriConfiguration :: Gen FriConfiguration
genFriConfiguration = defaultFriConfiguration . CapLength . (2 ^) <$> choose (0 :: Int, 4)


defaultFriConfiguration :: CapLength -> FriConfiguration
defaultFriConfiguration =
   FriConfiguration
  (Offset generator)
  (Omega . fromMaybe (error "could not find omega") $ primitiveNthRoot (fromIntegral dl))
  (DomainLength dl)
  (ExpansionFactor 2)
  (NumColinearityTests 4)
  where
    dl :: Int
    dl = 256



genProofStream :: FriConfiguration -> Gen ProofStream
genProofStream config =
  ProofStream
  <$> list (Range.linear 1 10) genCapCommitment
  <*> list (Range.linear 1 10) (list (Range.linear 1 10) genQuery)
  <*> choice [pure Nothing, Just <$> genCodeword config]
  <*> list (Range.linear 1 10) (list (Range.linear 1 10) genAuthPaths)


genAuthPaths :: Gen AuthPaths
genAuthPaths =
  AuthPaths
  <$> ((,,) <$> (A <$> genAuthPath)
            <*> (B <$> genAuthPath)
            <*> (C <$> genAuthPath))


genCommitment :: Gen Commitment
genCommitment = Commitment . MerkleHash <$> genByteString


genCapCommitment :: Gen CapCommitment
genCapCommitment = do
  n :: Int <- (2 ^) <$> choose (0, 6 :: Int)
  CapCommitment . fromMaybe (error "could not generate binary tree")
    . BinaryTree.fromList <$> vectorOf n genCommitment


genQuery :: Gen Query
genQuery = Query <$> ((,,) <$> (A <$> genScalar) <*> (B <$> genScalar) <*> (C <$> genScalar))


genAuthPath :: Gen AuthPath
genAuthPath = AuthPath <$> list (Range.linear 1 10) (Commitment . MerkleHash <$> genByteString)


genByteString :: Gen ByteString
genByteString = BS.pack <$> list (Range.linear 1 10) chooseAny


genCodeword :: FriConfiguration -> Gen Codeword
genCodeword config =
  Codeword <$> replicateM
  (config ^. #domainLength . #unDomainLength)
  genScalar


genLowDegreePoly :: FriConfiguration -> Gen (UnivariatePolynomial Scalar)
genLowDegreePoly config = do
  let maxDegree = getMaxDegree (config ^. #domainLength)
  coefs <- vectorOf maxDegree genScalar
  let monos :: [U x]
      monos = U <$> [0..maxDegree-1]
  pure . UnivariatePolynomial . Uni . FreeMod . Map.fromList
    . filter ((/= 0) . snd) $ zip monos coefs


genScalar :: Gen Scalar
genScalar = Scalar . fromIntegral <$> choose (0, cardinality - 1)


genBinaryTreeSize :: Gen Int
genBinaryTreeSize = (2 ^) <$> chooseInt (1, 8)


genBinaryTree :: Gen a -> Gen (Int, [a], BinaryTree a)
genBinaryTree g = do
  n <- genBinaryTreeSize
  xs <- vectorOf n g
  return (n, xs,
    fromMaybe (error "failed to generate binary tree")
      . BinaryTree.fromList $ xs)
