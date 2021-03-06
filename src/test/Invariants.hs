{-# LANGUAGE InstanceSigs #-}
module Main where

import Control.Monad.Random
import Control.Monad.Reader
import Test.Tasty
import Test.Tasty.QuickCheck as QC
import qualified Data.IntMap.Strict as Map 
import Data.Maybe

import SIR.Model
import SIR.Event
import SIR.SD
import Utils.GenEventSIR
import Utils.GenTimeSIR
import Utils.GenTimeCorrSIR as CorrSIR
import Utils.GenSIR
import Utils.Numeric
import Utils.Stats

import Debug.Trace

-- --quickcheck-replay=557780
-- --quickcheck-tests=1000
-- --quickcheck-verbose
-- --test-arguments=""
-- clear & stack test sir:sir-invariants-tests

main :: IO ()
main = do
  let t = testGroup "SIR Invariant Tests" 
          [ 
             QC.testProperty "SIR time correlated vs uncorrelated" prop_sir_time_timecorr_equal
          --  QC.testProperty "SIR SD invariant" prop_sir_sd_invariants
          --  QC.testProperty "SIR event-driven invariant" prop_sir_event_invariants
          --, QC.testProperty "SIR event-driven random event sampling invariant" prop_sir_random_invariants
          --, QC.testProperty "SIR time-driven invariant" prop_sir_time_invariants
          --, QC.testProperty "SIR time- and event-driven distribution" prop_sir_event_time_equal
          ]

  defaultMain t

--------------------------------------------------------------------------------
-- SIMULATION INVARIANTS
--------------------------------------------------------------------------------
prop_sir_event_invariants :: Positive Int    -- ^ beta, contact rate
                          -> Probability     -- ^ gamma, infectivity, within (0,1) range
                          -> Positive Double -- ^ delta, illness duration
                          -> [SIRState]      -- ^ population
                          -> Property
prop_sir_event_invariants (Positive cor) (P inf) (Positive ild) as = property $ do
  -- total agent count
  let n = length as

  -- run simulation UNRESTRICTED in both time and event count
  ret <- genEventSIR as cor inf ild (-1) (1/0)
  
  -- after a finite number of steps SIR will reach equilibrium, when there
  -- are no more infected agents. WARNING: this could be a potentially non-
  -- terminating computation but a correct SIR implementation will always
  -- lead to a termination of this
  let equilibriumData = takeWhile ((>0).snd3.snd) ret

  return (sirInvariants n equilibriumData)

prop_sir_time_invariants :: Positive Double -- ^ beta, contact rate
                         -> Probability     -- ^ gamma, infectivity, within (0,1) range
                         -> Positive Double -- ^ delta, illness duration
                         -> [SIRState]      -- ^ population
                         -> Property
prop_sir_time_invariants (Positive cor) (P inf) (Positive ild) as = property $ do
  -- total agent count
  let n = length as

  let dt = 0.1
  -- run simulation UNRESTRICTED TIME
  ret <- genTimeSIR as cor inf ild dt 0

  -- after a finite number of steps SIR will reach equilibrium, when there
  -- are no more infected agents. WARNING: this could be a potentially non-
  -- terminating computation but a correct SIR implementation will always
  -- lead to a termination of this 
  let equilibriumData = takeWhile ((>0).snd3.snd) ret

  return (sirInvariants n equilibriumData)

prop_sir_sd_invariants :: Positive Double -- ^ Susceptible agents
                       -> Positive Double -- ^ Infected agents
                       -> Positive Double -- ^ Recovered agents
                       -> Positive Double -- ^ Random beta, contact rate
                       -> Probability     -- ^ Random gamma, infectivity, within (0,1) range
                       -> Positive Double -- ^ Random delta, illness duration
                       -> Positive Double -- ^ Random time
                       -> Bool
prop_sir_sd_invariants (Positive s) (Positive i) (Positive r) 
                       (Positive cor) (P inf) (Positive ild) 
                       (Positive t)
      = sirInvariantsFloating (s + i + r) ret
  where
    -- NOTE: due to SD continuous nature it will take basically FOREVER to reach
    -- an infected of 0 => we always limit the duration but we do it randomly
    ret = runSIRSD s i r cor inf ild t

prop_sir_random_invariants :: Positive Int    -- ^ beta, contact rate
                           -> Probability     -- ^ gamma, infectivity, within (0,1) range
                           -> Positive Double -- ^ delta, illness duration
                           -> NonEmptyList SIRState -- ^ population
                           -> Property
prop_sir_random_invariants (Positive cor) (P inf) (Positive ild) (NonEmpty as) = property $ do
  -- total agent count
  let n = length as
  -- number of random events to generate
  let eventCount = 10000
  -- run simulation with random population and random events
  ret <- genRandomEventSIR as cor inf ild eventCount

  return (sirInvariants n ret)

sirInvariants :: Int                       -- ^ N total number of agents
              -> [(Time, (Int, Int, Int))] -- ^ simulation output for each step/event: (Time, (S,I,R))
              -> Bool
sirInvariants n aos = timeInc && aConst && susDec && recInc && infInv
  where
    (ts, sirs)  = unzip aos
    (ss, _, rs) = unzip3 sirs

    -- 1. time is monotonic increasing
    timeInc = allPairs (<=) ts
    -- 2. number of agents N stays constant in each step
    aConst = all agentCountInv sirs
    -- 3. number of susceptible S is monotonic decreasing
    susDec = allPairs (>=) ss
    -- 4. number of recovered R is monotonic increasing
    recInc = allPairs (<=) rs
    -- 5. number of infected I = N - (S + R)
    infInv = all infectedInv sirs

    agentCountInv :: (Int, Int, Int) -> Bool
    agentCountInv (s,i,r) = s + i + r == n

    infectedInv :: (Int, Int, Int) -> Bool
    infectedInv (s,i,r) = i == n - (s + r)

-- NOTE: invariants under floating-point are much more difficult to get right
-- because we are comparing floating point values which are evil anyway.
-- We removed infected invariant due to subtraction operation which f*** up
-- things with floating point, so we remove this propery as it follows from
-- the other ones anyway (even if it gets violated in this case)
sirInvariantsFloating :: Double -> [(Time, (Double, Double, Double))] -> Bool
sirInvariantsFloating n aos = timeInc && aConst && susDec && recInc
  where
    epsilon     = 0.0001
    (ts, sirs)  = unzip aos
    (ss, _, rs) = unzip3 sirs

    -- 1. time is monotonic increasing
    timeInc = allPairs (<=) ts
    -- 2. number of agents N stays constant in each step
    aConst = all agentCountInv sirs
    -- 3. number of susceptible S is monotonic decreasing
    susDec = allPairs (>=) ss
    -- 4. number of recovered R is monotonic increasing
    recInc = allPairs (<=) rs

    agentCountInv :: (Double, Double, Double) -> Bool
    agentCountInv (s,i,r) = compareDouble n (s + i + r) epsilon

-- NOTE: need to use mann whitney because both produce bi-modal distributions
-- thus t-test does not work because it assumes normally distributed samples
prop_sir_event_time_equal :: Positive Int    -- ^ Random beta, contact rate
                          -> Probability     -- ^ Random gamma, infectivity, within (0,1) range
                          -> Positive Double -- ^ Random delta, illness duration
                          -> TimeRange       -- ^ Random time to run, within (0, 50) range)
                          -> [SIRState]      -- ^ Random population
                          -> Property
prop_sir_event_time_equal
    (Positive cor) (P inf) (Positive ild) (T t) as = checkCoverage $ do
  -- run 100 replications
  let repls = 100
 
  -- run 100 replications for time- and event-driven simulation
  (ssTime, isTime, rsTime) <- 
    unzip3 . map int3ToDbl3 <$> genTimeSIRRepls repls as (fromIntegral cor) inf ild 0.01 t
  (ssEvent, isEvent, rsEvent) <- 
    unzip3 . map int3ToDbl3 <$> genEventSIRRepls repls as cor inf ild (-1) t
  
  let p = 0.05

  let ssTest = mannWhitneyTwoSample ssTime ssEvent p
      isTest = mannWhitneyTwoSample isTime isEvent p
      rsTest = mannWhitneyTwoSample rsTime rsEvent p

  let allPass = fromMaybe True ssTest &&
                fromMaybe True isTest &&
                fromMaybe True rsTest 

  --return $ trace (show allPass) 
  return $
    cover 90 allPass "SIR event- and time-driven produce equal distributions" True

-- NOTE: need to use mann whitney because both produce bi-modal distributions
-- thus t-test does not work because it assumes normally distributed samples
-- NOTE: according to tests we are not reaching 100% similarty but "only" 96%, the question is
-- whether this means that there is a difference or that it is so small that we can neglect it?

-- TRIED WITH cover of 90
-- OK (7822.74s)
--    +++ OK, passed 400 tests (96.0% SIR correlated and uncorrelated time-driven produce equal distributions).
-- TRIED WITH cover of 100
-- FAIL (2634.78s)
--     *** Failed! Insufficient coverage (after 100 tests):
--     96% SIR correlated and uncorrelated time-driven produce equal distributions
    
--     Only 96% SIR correlated and uncorrelated time-driven produce equal distributions, but expected 100%
--     Use --quickcheck-replay=589446 to reproduce.

-- CHECKED ALSO AGAINST A COMPARISON OF UNCORRELATED WITH ITSELF (but using 2 different initial RNGs)
-- FAIL (2174.63s)
--     *** Failed! Insufficient coverage (after 100 tests):
--     97% SIR correlated and uncorrelated time-driven produce equal distributions
    
--     Only 97% SIR correlated and uncorrelated time-driven produce equal distributions, but expected 100%
--     Use --quickcheck-replay=232632 to reproduce.

-- CHECKED ALSO AGAINST A COMPARISON OF CORRELATED WITH ITSELF (but using 2 different initial RNGs)
-- FAIL (1644.38s)
--     *** Failed! Insufficient coverage (after 100 tests):
--     96% SIR correlated and uncorrelated time-driven produce equal distributions
    
--     Only 96% SIR correlated and uncorrelated time-driven produce equal distributions, but expected 100%
--     Use --quickcheck-replay=395489 to reproduce.


-- 1 out of 1 tests failed (2634.78s)
prop_sir_time_timecorr_equal :: Positive Int    -- ^ Random beta, contact rate
                             -> Probability     -- ^ Random gamma, infectivity, within (0,1) range
                             -> Positive Double -- ^ Random delta, illness duration
                             -> TimeRange       -- ^ Random time to run, within (0, 50) range)
                             -> [SIRState]      -- ^ Random population
                             -> Property
prop_sir_time_timecorr_equal
    (Positive cor) (P inf) (Positive ild) (T t) as = checkCoverage $ do
  -- run 100 replications
  let repls = 100
 
  -- run 100 replications for both the correlated and uncorrelated
  -- time-driven simulation
  (ssTime, isTime, rsTime) <- 
    unzip3 . map int3ToDbl3 <$> genTimeSIRRepls repls as (fromIntegral cor) inf ild 0.01 t
  (ssTimeCorr, isTimeCorr, rsTimeCorr) <- 
    unzip3 . map int3ToDbl3 <$> CorrSIR.genTimeCorrSIRRepls repls as (fromIntegral cor) inf ild 0.01 t

  -- let ssTimeCorr = ssTime
  --     isTimeCorr = isTime
  --     rsTimeCorr = rsTime

  let p = 0.05

  let ssTest = mannWhitneyTwoSample ssTime ssTimeCorr p
      isTest = mannWhitneyTwoSample isTime isTimeCorr p
      rsTest = mannWhitneyTwoSample rsTime rsTimeCorr p

  -- let ssTest = ssTime == ssTimeCorr
  --     isTest = isTime == isTimeCorr
  --     rsTest = rsTime == rsTimeCorr

  let allPass = fromMaybe True ssTest &&
                fromMaybe True isTest &&
                fromMaybe True rsTest 

  -- let allPass = ssTest &&
  --               isTest &&
  --               rsTest 

  return $ trace (show allPass) 
  --return $
    cover 100 allPass "SIR correlated and uncorrelated time-driven produce equal distributions" True

-- 1 out of 1 tests failed (2634.78s)
prop_sir_time_timecorr_equal' :: Property
prop_sir_time_timecorr_equal' = checkCoverage $ do
  -- run 100 replications
  let repls = 100
 
  let as  = replicate 99 Susceptible ++ [Infected]
      cor = 5 :: Int
      inf = 0.05
      ild = 15
      t   = 50

  -- run 100 replications for both the correlated and uncorrelated
  -- time-driven simulation
  (ssTime, isTime, rsTime) <- 
    unzip3 . map int3ToDbl3 <$> genTimeSIRRepls repls as (fromIntegral cor) inf ild 0.01 t
  (ssTimeCorr, isTimeCorr, rsTimeCorr) <- 
    unzip3 . map int3ToDbl3 <$> genTimeSIRRepls repls as (fromIntegral cor) inf ild 0.01 t

  let p = 0.05

  let ssTest = mannWhitneyTwoSample ssTime ssTimeCorr p
      isTest = mannWhitneyTwoSample isTime isTimeCorr p
      rsTest = mannWhitneyTwoSample rsTime rsTimeCorr p

  -- let ssTest = ssTime == ssTimeCorr
  --     isTest = isTime == isTimeCorr
  --     rsTest = rsTime == rsTimeCorr

  let allPass = fromMaybe True ssTest &&
                fromMaybe True isTest &&
                fromMaybe True rsTest 

  -- let allPass = ssTest &&
  --               isTest &&
  --               rsTest 

  return $ trace (show allPass) 
  --return $
    cover 100 allPass "SIR correlated and uncorrelated time-driven produce equal distributions" True


-- NOTE: all these properties are already implicitly checked in the agent 
-- specifications and sir invariants
-- > Recovered Agent generates no events and stays recovered FOREVER. This means:
--  pre-condition:   in Recovered state and ANY event
--  post-condition:  in Recovered state and 0 scheduled events
-- > Susceptible Agent MIGHT become Infected and Recovered
-- > Infected Agent will NEVER become Susceptible and WILL become Recovered

--------------------------------------------------------------------------------
-- CUSTOM GENERATOR, ONLY RELEVANT TO STATEFUL TESTING 
--------------------------------------------------------------------------------
genRandomEventSIR :: [SIRState]
                  -> Int
                  -> Double
                  -> Double 
                  -> Integer
                  -> Gen [(Time, (Int, Int, Int))]
genRandomEventSIR as cor inf ild maxEvents = do
    g <- genStdGen 

    -- ignore initial events
    let (am0, _) = evalRand (initSIR as cor inf ild) g
        ais = Map.keys am0

    -- infinite stream of events, prevents us from calling genQueueItem in
    -- the execEvents function - lazy evaluation is really awesome!
    evtStream <- genQueueItemStream 0 ais
    
    return $ evalRand (runReaderT (executeEvents maxEvents evtStream am0) ais) g
  where
    executeEvents :: RandomGen g
                  => Integer
                  -> [QueueItem SIREvent]
                  -> AgentMap (SIRMonad g) SIREvent SIRState
                  -> ReaderT [AgentId] (Rand g) [(Time, (Int, Int, Int))]
    executeEvents 0 _ _  = return []
    executeEvents _ [] _ = return []
    executeEvents n (evt:es) am = do
      retMay <- processEvent am evt 
      case retMay of 
        Nothing -> executeEvents (n-1) es am
        -- ignore events produced by agents
        (Just (am', _)) -> do
          let s = (eventTime evt, aggregateAgentMap am)
          ss <- executeEvents (n-1) es am'
          return (s : ss)

--------------------------------------------------------------------------------
-- UTILS
--------------------------------------------------------------------------------
snd3 :: (a,b,c) -> b
snd3 (_,b,_) = b

allPairs :: (Ord a, Num a) => (a -> a -> Bool) -> [a] -> Bool
allPairs f xs = all (uncurry f) (pairs xs)

pairs :: [a] -> [(a,a)]
pairs xs = zip xs (tail xs)