{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ViewPatterns #-}


module Stark.Fri
  ( numRounds
  , evalDomain
  , sampleIndex
  , sampleIndices
  , fiatShamirSeed
  , fiatShamirChallenge
  , splitAndFold
  , commitPhase
  , commitRound
  , commitCodeword
  , addCodeword
  , addCommitment
  , openCodeword
  , queryRound
  , queryPhase
  , prove

  , getLastOmega
  , getLastOffset
  , getAlphas
  , verify
  ) where


import Codec.Serialise (serialise)
import Control.Lens ((^.))
import Data.Bits (shift, xor)
import Data.ByteString (ByteString, unpack)
import Data.ByteString.Lazy (toStrict)
import Data.Generics.Labels ()
import Data.List (find, inits)
import Data.Maybe (fromMaybe)
import Data.Set (Set, size, member, insert, toList)
import Data.Tuple.Extra (fst3, snd3)

import Stark.BinaryTree (fromList)
import Stark.FiniteField (sample)
import Stark.Fri.Types (DomainLength (..), ExpansionFactor (..), NumColinearityTests (..), Offset (..), Omega (..), RandomSeed (..), ListSize (..), ReducedListSize (..), Index (..), SampleSize (..), ReducedIndex (..), Codeword (..), ProofStream (..), Challenge (..), FriConfiguration (..), PolynomialValues (..))
import Stark.Hash (hash)
import Stark.MerkleTree (commit, open)
import Stark.Types.AuthPath (AuthPath)
import Stark.Types.Commitment (Commitment)
import Stark.Types.Scalar (Scalar)
import Stark.UnivariatePolynomial (degree, interpolate)


numRounds :: DomainLength -> ExpansionFactor -> NumColinearityTests -> Int
numRounds (DomainLength d) (ExpansionFactor e) (NumColinearityTests n) =
  if fromIntegral d > e && 4 * n < d
  then 1 + numRounds
           (DomainLength (d `div` 2))
           (ExpansionFactor e)
           (NumColinearityTests n)
  else 0


evalDomain :: Offset -> Omega -> DomainLength -> [Scalar]
evalDomain (Offset o) (Omega m) (DomainLength d)
  = [o * (m ^ i) | i <- [0..d-1]]


sampleIndex :: ByteString -> ListSize -> Index
sampleIndex bs (ListSize len) =
  foldl (\acc b -> (acc `shift` 8) `xor` fromIntegral b) 0 (unpack bs)
  `mod` Index len


sampleIndices :: RandomSeed -> ListSize -> ReducedListSize -> SampleSize -> Set Index
sampleIndices seed ls rls@(ReducedListSize rls') (SampleSize n)
  | n > rls' = error "cannot sample more indices than available in last codeword"
  | n >  2 * rls' = error "not enough entropy in indices wrt last codeword"
  | otherwise =
    fromMaybe (error "the impossible has happened: sampleIndices reached the end of the list")
  . find ((>= n) . size)
  $ fst3 <$> iterate (sampleIndicesStep seed ls rls) (mempty, mempty, 0)


sampleIndicesStep :: RandomSeed
                  -> ListSize
                  -> ReducedListSize
                  -> (Set Index, Set ReducedIndex, Int)
                  -> (Set Index, Set ReducedIndex, Int)
sampleIndicesStep (RandomSeed seed) ls (ReducedListSize rls)
                  (indices, reducedIndices, counter)
  = let index = sampleIndex (hash (seed <> toStrict (serialise counter))) ls
        reducedIndex = ReducedIndex $ unIndex index `mod` rls
    in if reducedIndex `member` reducedIndices
       then (indices, reducedIndices, counter+1)
       else (insert index indices, insert reducedIndex reducedIndices, counter+1)


fiatShamirSeed :: ProofStream -> RandomSeed
fiatShamirSeed = RandomSeed . hash . toStrict . serialise


fiatShamirChallenge :: ProofStream -> Challenge
fiatShamirChallenge = Challenge . sample . unRandomSeed . fiatShamirSeed


splitAndFold :: Omega -> Offset -> Codeword -> Challenge -> Codeword
splitAndFold (Omega omega) (Offset offset) (Codeword codeword) (Challenge alpha) =
  let n = length codeword
      (l, r) = splitAt (n `quot` 2) codeword
  in Codeword $
  [ recip 2 * ( ( 1 + alpha / (offset * (omega^i)) ) * xi
              + ( 1 - alpha / (offset * (omega^i)) ) * xj )
  | (i, xi, xj) <- zip3 [(0 :: Integer)..] l r ]


addCommitment :: Commitment -> ProofStream -> ProofStream
addCommitment c (ProofStream commitments codewords authPaths)
  = ProofStream (c : commitments) codewords authPaths


addCodeword :: Codeword -> ProofStream -> ProofStream
addCodeword c (ProofStream commitments codewords authPaths)
  = ProofStream commitments (c : codewords) authPaths


addAuthPath :: AuthPath -> ProofStream -> ProofStream
addAuthPath p (ProofStream commitments codewords authPaths)
  = ProofStream commitments codewords (p : authPaths)


commitCodeword :: Codeword -> Commitment
commitCodeword = commit . fromMaybe (error "codeword is not a binary tree") . fromList . unCodeword


openCodeword :: Codeword -> Index -> AuthPath
openCodeword (Codeword xs) (Index i) =
  open (fromIntegral i) (fromMaybe (error "codeword is not a binary tree") (fromList xs))


commitPhase :: DomainLength
            -> ExpansionFactor
            -> NumColinearityTests
            -> Omega
            -> Offset
            -> Codeword
            -> ProofStream
            -> (ProofStream, [Codeword])
commitPhase domainLength expansionFactor numColinearityTests omega offset codeword proofStream
  = let n = numRounds domainLength expansionFactor numColinearityTests
        (proofStream', codewords', codeword', _, _) =
          (iterate commitRound (proofStream, [], codeword, omega, offset))
          !! (n-1)
    in (addCodeword codeword' proofStream', codeword' : codewords')


commitRound ::(ProofStream, [Codeword], Codeword, Omega, Offset)
            -> (ProofStream, [Codeword], Codeword, Omega, Offset)
commitRound (proofStream, codewords, codeword, omega, offset) =
  let root = commitCodeword codeword
      alpha = fiatShamirChallenge proofStream
      codeword' = splitAndFold omega offset codeword alpha
  in (addCommitment root proofStream, codeword : codewords, codeword', omega^two, offset^two)
  where two :: Integer
        two = 2


queryRound :: NumColinearityTests
           -> (Codeword, Codeword)
           -> [Index]
           -> ProofStream
           -> ProofStream
queryRound (NumColinearityTests n) (Codeword currentCodeword, Codeword nextCodeword)
           cIndices proofStream =
  let aIndices = take n cIndices
      bIndices = take n $ (+ (Index (length currentCodeword `quot` 2))) <$> cIndices
      leafProofElems = zipWith3 (\a b c -> Codeword [a,b,c])
                       ((currentCodeword !!) . fromIntegral <$> aIndices)
                       ((currentCodeword !!) . fromIntegral <$> bIndices)
                       ((nextCodeword !!) . fromIntegral <$> cIndices)
      authPathProofElems =
        (openCodeword (Codeword currentCodeword) <$> aIndices)
         <> (openCodeword (Codeword currentCodeword) <$> bIndices)
         <> (openCodeword (Codeword nextCodeword) <$> cIndices)
  in foldl (flip addAuthPath)
     (foldl (flip addCodeword) proofStream (reverse leafProofElems))
     (reverse authPathProofElems)


queryPhase :: NumColinearityTests -> [Codeword] -> [Index] -> ProofStream -> ProofStream
queryPhase numColinearityTests codewords indices proofStream =
  snd3 $ (iterate f (indices, proofStream, 0)) !! (length codewords - 2)
  where
    f :: ([Index], ProofStream, Int) -> ([Index], ProofStream, Int)
    f (indices', proofStream', i) =
      ( (`mod` (Index (length (unCodeword (codewords !! i)) `quot` 2))) <$> indices
      , queryRound numColinearityTests (codewords !! i, codewords !! (i+1)) indices' proofStream'
      , i+1
      )


prove :: FriConfiguration -> Codeword -> (ProofStream, [Index])
prove (FriConfiguration offset omega domainLength expansionFactor numColinearityTests) codeword
  | unDomainLength domainLength == length (unCodeword codeword) =
    let (proofStream0, codewords) =
          commitPhase domainLength expansionFactor numColinearityTests
                      omega offset codeword (ProofStream [] [] [])
        indices = toList $ sampleIndices
                           (fiatShamirSeed proofStream0)
                           (ListSize (length (unCodeword (codewords !! 1))))
                           (ReducedListSize (length (unCodeword (codewords !! (length codewords - 1)))))
                           (SampleSize (unNumColinearityTests numColinearityTests))
        proofStream1 = queryPhase numColinearityTests codewords indices proofStream0
    in (proofStream1, indices)
  | otherwise = error "domain length does not match length of initial codeword"


getLastOmega :: FriConfiguration -> Omega
getLastOmega config =
  iterate (^ (2 :: Int)) (config ^. #omega)
  !! numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)


getLastOffset :: FriConfiguration -> Offset
getLastOffset config =
  iterate (^ (2 :: Int)) (config ^. #offset)
  !! numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)


-- Takes the reversed list of commitments from the proof stream and provides
-- the list of corresponding challenges.
getAlphas :: [Commitment] -> [Challenge]
getAlphas roots =
  fiatShamirChallenge . (\cs -> ProofStream cs [] []) <$> inits roots


-- Returns evaluations of the polynomial at the indices if the proof is valid, or Nothing otherwise.
verify :: FriConfiguration -> ProofStream -> Maybe PolynomialValues
verify config proofStream =
  let roots = reverse (proofStream ^. #commitments)
      alphas = getAlphas roots
      lastOmega = getLastOmega config
      lastOffset = getLastOffset config
      nr = numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)
  in case (proofStream ^. #commitments, proofStream ^. #codewords) of
    (lastRoot : _, lastCodeword : (reverse -> codewords)) ->
      let lastCodewordLength = length (unCodeword lastCodeword)
          lastDomain = [ unOffset lastOffset * (unOmega lastOmega ^ i)
                       | i <- [0 .. lastCodewordLength] ]
          poly = interpolate (zip lastDomain (unCodeword lastCodeword))
          maxDegree = floor (fromIntegral lastCodewordLength
                           / unExpansionFactor (config ^. #expansionFactor)) - 1
          dl = unDomainLength (config ^. #domainLength)
          topLevelIndices =
            sampleIndices
              (fiatShamirSeed
                (ProofStream (proofStream ^. #commitments) [lastCodeword] []))
              (ListSize $ dl `shift` negate 2)
              (ReducedListSize $ dl `shift` negate (nr - 1))
      in if degree poly > maxDegree
         then Nothing
         else todo
    _ -> Nothing


todo :: a
todo = todo
