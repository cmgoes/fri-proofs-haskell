module Stark.MerkleTree
  ( dataToLeaf
  , commit
  , commit_
  , open_
  , open
  ) where


import Codec.Serialise (Serialise, serialise)
import qualified Crypto.Hash.BLAKE2.BLAKE2b as BLAKE2b
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as BSL

import qualified Stark.BinaryTree as Tree
import Stark.Types.AuthPath (AuthPath (AuthPath))
import Stark.Types.BinaryTree (BinaryTree (IsLeaf, IsNode))
import Stark.Types.Commitment (Commitment (Commitment, unCommitment))
import Stark.Types.Leaf (Leaf (Leaf))
import Stark.Types.MerkleHash (MerkleHash (MerkleHash))


hash :: ByteString -> ByteString
hash = BLAKE2b.hash 64 mempty


hashData :: Serialise a => a -> MerkleHash
hashData = MerkleHash . hash . BSL.toStrict . serialise


dataToLeaf :: Serialise a => a -> Leaf
dataToLeaf = Leaf . hashData


commit :: Serialise a => BinaryTree a -> Commitment
commit = commit_ . fmap hashData


commit_ :: BinaryTree MerkleHash -> Commitment
commit_ (IsLeaf x) = Commitment x
commit_ (IsNode x y) = Commitment (hashData (commit x, commit y))


open_ :: Integer -> BinaryTree MerkleHash -> AuthPath
open_ 0 (IsNode (IsLeaf _) (IsLeaf x)) = AuthPath [x]
open_ 1 (IsNode (IsLeaf x) (IsLeaf _)) = AuthPath [x]
open_ i t@(IsNode x y) =
  let n = Tree.size t
      m = n `quot` 2
  in if i < m
     then (open_ i x) <> AuthPath [unCommitment $ commit_ y]
     else (open_ (i-m) x) <> AuthPath [unCommitment $ commit_ y]
open_ _ _ = error "open_ pattern match failure"


open :: Serialise a => Integer -> BinaryTree a -> AuthPath
open i xs = open_ i (hashData <$> xs)
