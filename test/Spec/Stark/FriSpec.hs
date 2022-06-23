{-# LANGUAGE OverloadedLabels #-}


module Spec.Stark.FriSpec ( spec ) where


-- import Control.Lens ((^.))
-- import qualified Data.Map as Map

import Spec.Prelude
import Spec.Gen (genFriConfiguration, genProofStream, genLowDegreePoly)
import Stark.Fri (verify, prove, getCodeword)
-- import Stark.Fri.Types (PolynomialValues (..))
-- import Stark.UnivariatePolynomial (evaluate)


spec :: Spec
spec = describe "Fri" $ do
  soundnessTest
  completenessTest
  -- evaluationTest


soundnessTest :: Spec
soundnessTest =
  it "rejects invalid proofs" $
    forAll genFriConfiguration $ \config ->
      forAll (genProofStream config) $ \proof ->
        verify config proof `shouldBe` Nothing


completenessTest :: Spec
completenessTest =
  it "creates proofs of true statements which are accepted" $
    forAll genFriConfiguration $ \config ->
      forAll (genLowDegreePoly config) $ \poly -> 
        verify config (fst (prove config (getCodeword config poly))) `shouldNotBe` Nothing


-- evaluationTest :: Spec
-- evaluationTest =
--   it "produces correct openings at the indices" $
--     forAll genFriConfiguration $ \config ->
--       forAll (genLowDegreePoly config) $ \poly ->
--         let codeword = getCodeword config poly
--             (proofStream, indices) = prove config codeword
--             openings = PolynomialValues . Map.fromList . zip indices
--               $ evaluate poly . ((config ^. #omega . #unOmega) ^) <$> indices
--         in verify config proofStream `shouldBe` Just openings
