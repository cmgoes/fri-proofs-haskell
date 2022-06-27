{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ViewPatterns #-}
{-# OPTIONS_GHC -Wno-unused-matches #-}

module Stark.Fri
  ( getMaxDegree
  , numRounds
  , evalDomain
  , getCodeword
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
  , addQuery
  , addAuthPath
  , openCodeword
  , queryRound
  , queryPhase
  , emptyProofStream
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
import Data.List (find, inits, zip4, zip5)
import Data.List.Safe ((!!))
import Data.Maybe (fromMaybe)
import Data.Set (Set)
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Tuple.Extra (fst3, snd3, thd3)
import Debug.Trace (trace)
import Prelude hiding ((!!))

import Stark.BinaryTree (fromList)
import Stark.FiniteField (sample)
import Stark.Fri.Types (DomainLength (..), ExpansionFactor (..), NumColinearityTests (..), Offset (..), Omega (..), RandomSeed (..), ListSize (..), ReducedListSize (..), SampleSize (..), ReducedIndex (..), Codeword (..), ProofStream (..), Challenge (..), FriConfiguration (..), PolynomialValues (..), AY (..), BY (..), CY (..), Query (..))
import Stark.Hash (hash)
import qualified Stark.MerkleTree as Merkle
import Stark.Types.AuthPath (AuthPath)
import Stark.Types.Commitment (Commitment)
import Stark.Types.Index (Index (..))
import Stark.Types.Scalar (Scalar)
import Stark.Types.UnivariatePolynomial (UnivariatePolynomial)
import Stark.UnivariatePolynomial (degree, interpolate, areColinear, evaluate)


getMaxDegree :: DomainLength -> Int
getMaxDegree (DomainLength d) = floor (logBase 2 (fromIntegral d) :: Double)


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


getCodeword :: FriConfiguration -> UnivariatePolynomial -> Codeword
getCodeword config poly =
  Codeword $ evaluate poly <$> evalDomain (config ^. #offset) (config ^. #omega) (config ^. #domainLength)


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
  . find ((>= n) . Set.size)
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
    in if reducedIndex `Set.member` reducedIndices
       then (indices, reducedIndices, counter+1)
       else ( Set.insert index indices
            , Set.insert reducedIndex reducedIndices, counter+1 )


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


emptyProofStream :: ProofStream
emptyProofStream = ProofStream [] [] Nothing []


addCommitment :: Commitment -> ProofStream -> ProofStream
addCommitment c (ProofStream commitments queries codewords authPaths)
  = ProofStream (commitments ++ [c]) queries codewords authPaths


addQuery :: Query -> ProofStream -> ProofStream
addQuery q (ProofStream commitments queries codewords authPaths)
  = ProofStream commitments (queries ++ [q]) codewords authPaths


addCodeword :: Codeword -> ProofStream -> ProofStream
addCodeword c (ProofStream commitments queries Nothing authPaths)
  = ProofStream commitments queries (Just c) authPaths
addCodeword _ _ = error "tried to add the last codeword but it is already present"


addAuthPath :: AuthPath -> ProofStream -> ProofStream
addAuthPath p (ProofStream commitments queries codewords authPaths)
  = ProofStream commitments queries codewords (authPaths ++ [p])


commitCodeword :: Codeword -> Commitment
commitCodeword = Merkle.commit . fromMaybe (error "codeword is not a binary tree") . fromList . unCodeword


openCodeword :: Codeword -> Index -> AuthPath
openCodeword (Codeword xs) (Index i) =
  Merkle.open (fromIntegral i) (fromMaybe (error "codeword is not a binary tree") (fromList xs))


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
          fromMaybe (error "could not find last commit round") $
          (iterate commitRound (proofStream, [], codeword, omega, offset))
          !! (n-1)
    in ( addCodeword codeword'
         ( addCommitment (commitCodeword codeword')
           proofStream' )
       , codewords' ++ [codeword'] )


commitRound ::(ProofStream, [Codeword], Codeword, Omega, Offset)
            -> (ProofStream, [Codeword], Codeword, Omega, Offset)
commitRound (proofStream, codewords, codeword, omega, offset) =
  let root = commitCodeword codeword
      alpha = fiatShamirChallenge proofStream
      codeword' = splitAndFold omega offset codeword alpha
  in (addCommitment root proofStream, codewords ++ [codeword], codeword', omega^two, offset^two)
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
      leafProofElems = fromMaybe (error $ "missing leaf: " <> show (length currentCodeword, length nextCodeword, cIndices, aIndices, bIndices)) <$>
         zipWith3 (\a b c -> Query <$> ((,,) <$> (AY <$> a) <*> (BY <$> b) <*> (CY <$> c)))
         ((currentCodeword !!) <$> aIndices)
         ((currentCodeword !!) <$> bIndices)
         ((nextCodeword !!) <$> cIndices)
      authPathProofElems =
        (openCodeword (Codeword currentCodeword) <$> aIndices)
         <> (openCodeword (Codeword currentCodeword) <$> bIndices)
         <> (openCodeword (Codeword nextCodeword) <$> cIndices)
  in foldl (flip addAuthPath)
     (foldl (flip addQuery) proofStream (leafProofElems))
     (authPathProofElems)


-- Index out of range error in queryPhase
queryPhase :: NumColinearityTests -> [Codeword] -> [Index] -> ProofStream -> ProofStream
queryPhase numColinearityTests codewords indices proofStream =
  snd3 . fromMaybe (error "could not find last query round")
    $ (iterate f (indices, proofStream, 0)) !! max 0 (length codewords - 2)
  where
    f :: ([Index], ProofStream, Int) -> ([Index], ProofStream, Int)
    f (indices', proofStream', i) =
      ( (`mod` (Index (length (unCodeword (e 1 (codewords !! i))) `quot` 2)))
        <$> indices'
      , queryRound numColinearityTests (e 2 (codewords !! i), e 3 (codewords !! (i+1))) indices' proofStream'
      , i+1
      )

    e :: Int -> Maybe a -> a
    e x = fromMaybe (error ("missing codeword " <> show x))


prove :: FriConfiguration -> Codeword -> (ProofStream, [Index])
prove (FriConfiguration offset omega domainLength expansionFactor numColinearityTests) codeword
  | unDomainLength domainLength == length (unCodeword codeword) =
    let (proofStream0, codewords) =
          commitPhase domainLength expansionFactor numColinearityTests
                      omega offset codeword emptyProofStream
        indices = Set.elems $ sampleIndices
          (fiatShamirSeed proofStream0)
          (ListSize (length (unCodeword (fromMaybe (error "missing second codeword") (codewords !! (1 :: Int))))))
          (ReducedListSize (length (unCodeword (fromMaybe (error "missing last codeword") (codewords !! (length codewords - 1))))))
                    (SampleSize (unNumColinearityTests numColinearityTests))
        proofStream1 = queryPhase numColinearityTests codewords indices proofStream0
    in (proofStream1, indices)
  | otherwise = error "domain length does not match length of initial codeword"


getLastOmega :: FriConfiguration -> Omega
getLastOmega config =
  let nr = numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)
  in (config ^. #omega) ^ (2 * (nr - 1))


getLastOffset :: FriConfiguration -> Offset
getLastOffset config =
  let nr = numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)
  in (config ^. #offset) ^ (2 * (nr - 1))


-- Takes the list of commitments from the proof stream and provides
-- the list of corresponding challenges.
getAlphas :: [Commitment] -> [Challenge]
getAlphas roots =
  fiatShamirChallenge . (\cs -> ProofStream cs [] Nothing []) <$> inits roots


-- Break a list into equal-sized sublists.
segment :: Int -> [a] -> [[a]]
segment n xs =
  case splitAt n xs of
    (ys,[]) -> [ys]
    (ys,yss) -> ys : segment n yss


-- Returns evaluations of the polynomial at the indices if the proof is valid, or Nothing otherwise.
verify :: FriConfiguration -> ProofStream -> Maybe PolynomialValues
verify config proofStream =
  let roots = proofStream ^. #commitments
      alphas = getAlphas roots
      lastOmega = getLastOmega config
      lastOffset = getLastOffset config
      nr = numRounds (config ^. #domainLength) (config ^. #expansionFactor) (config ^. #numColinearityTests)
      lastRoot = fromMaybe (error "could not find last root") $ roots !! (length roots - 1)
  in case (proofStream ^. #lastCodeword) of
    (Just lastCodeword) ->
      let lastCodewordLength = length (unCodeword lastCodeword)
          lastDomain = [ unOffset lastOffset * (unOmega lastOmega ^ i)
                       | i <- [0 .. lastCodewordLength - 1] ]
          poly = interpolate (zip lastDomain (unCodeword lastCodeword))
          maxDegree = getMaxDegree (config ^. #domainLength)
          dl = unDomainLength (config ^. #domainLength)
          nt = unNumColinearityTests (config ^. #numColinearityTests)
          topLevelIndices =
            Set.elems $ sampleIndices
              (fiatShamirSeed
                (ProofStream (proofStream ^. #commitments) [] (Just lastCodeword) []))
              (ListSize $ dl `shift` negate 2)
              (ReducedListSize $ dl `shift` negate (nr - 1))
              (SampleSize nt)
      in if lastRoot /= commitCodeword lastCodeword || degree poly > maxDegree
         then trace (if lastRoot == commitCodeword lastCodeword
                     then "degree poly > maxDegree"
                     else "lastRoot /= commitCodeword lastCodeword")
              Nothing
         else mconcat <$> sequence
              [ verifyRound config topLevelIndices r alpha rootPair q p
              | (r, alpha, rootPair, q, p) <-
                  zip5 [0 .. nr - 2]
                       alphas
                       (zip roots (drop 1 roots))
                       (segment nt (proofStream ^. #queries))
                       (segment nt (proofStream ^. #authPaths))
              ]
    _ -> trace "missing last codeword" Nothing


verifyRound :: FriConfiguration -> [Index] -> Int -> Challenge -> (Commitment, Commitment) -> [Query] -> [AuthPath] -> Maybe PolynomialValues
verifyRound config topLevelIndices r alpha (root, nextRoot) qs authPaths =
  let omega = (config ^. #omega) ^ ((2 :: Integer) ^ r)
      offset = (config ^. #offset) ^ ((2 :: Integer) ^ r)
      dl = config ^. #domainLength . #unDomainLength
      cIndices = (`mod` (fromIntegral (dl `shift` negate (r+1)))) <$> topLevelIndices
      aIndices = cIndices
      bIndices = (+ fromIntegral (dl `shift` negate (r+1))) <$> aIndices
      ays = fst3 . unQuery <$> qs
      bys = snd3 . unQuery <$> qs
      cys = thd3 . unQuery <$> qs
      polyVals = PolynomialValues . Map.fromList
               $ (zip aIndices (unAY <$> ays)) <> (zip bIndices (unBY <$> bys))
      f = (* unOffset offset) . (unOmega omega ^)
      --colinearityChecks = all areColinear
      --  $ (\(a,b,c) -> [a,b,c])
      --  <$> zip3 (zip (f <$> aIndices) (unAY <$> ays))
      --           (zip (f <$> bIndices) (unBY <$> bys))
      --           (zip (repeat (unChallenge alpha)) (unCY <$> cys))
      colinearityChecks = all areColinear
        $ (\(a, b) -> [a,b])
          <$> (zip (zip (f <$> aIndices) (unAY <$> ays))
                   (zip (f <$> bIndices) (unBY <$> bys)))
      aAuthPathChecks = all (uncurry4 Merkle.verify)
        $ zip4 (repeat root) aIndices authPaths (unAY <$> ays)
      bAuthPathChecks = all (uncurry4 Merkle.verify)
        $ zip4 (repeat root) bIndices authPaths (unBY <$> bys)
      cAuthPathChecks = all (uncurry4 Merkle.verify)
        $ zip4 (repeat nextRoot) cIndices authPaths (unCY <$> cys)
      authPathChecks = aAuthPathChecks && bAuthPathChecks && cAuthPathChecks
  in if colinearityChecks && authPathChecks
     then Just polyVals
     else if colinearityChecks
          then trace "auth path check failed" Nothing
          else trace "colinearity check failed" Nothing


uncurry4 :: (a -> b -> c -> d -> e) -> (a, b, c, d) -> e
uncurry4 f (a, b, c, d) = f a b c d
