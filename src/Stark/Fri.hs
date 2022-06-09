module Stark.Fri
  ( numRounds
  , evalDomain
  , sampleIndex
  , sampleIndices
  , fiatShamirSeed
  ) where


import Codec.Serialise (serialise)
import Data.Bits (shift, xor)
import Data.ByteString (ByteString, unpack)
import Data.ByteString.Lazy (toStrict)
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Set (Set, size, member, insert)
import Data.Text (pack)
import Data.Text.Encoding (encodeUtf8)
import Data.Tuple.Extra (fst3)

import Stark.Fri.Types (DomainLength (..), ExpansionFactor (..), NumColinearityTests (..), Offset (..), Omega (..), RandomSeed (..), ListSize (..), ReducedListSize (..), Index (..), SampleSize (..), ReducedIndex (..), Codeword (..), ProofStream (..))
import Stark.Hash (hash)
import Stark.Types.Scalar (Scalar)


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
  = let index = sampleIndex (hash (seed <> encodeUtf8 (pack (show counter)))) ls
        reducedIndex = ReducedIndex $ unIndex index `mod` rls
    in if reducedIndex `member` reducedIndices
       then (indices, reducedIndices, counter+1)
       else (insert index indices, insert reducedIndex reducedIndices, counter+1)


fiatShamirSeed :: ProofStream -> RandomSeed
fiatShamirSeed = RandomSeed . hash . toStrict . serialise