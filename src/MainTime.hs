module Main where

import System.Random

-- import Export.Compress
-- import Export.CSV
import SIR.Time

seed :: Int
seed = 42

main :: IO ()
main = do
  let g   = mkStdGen seed
  --g <- getStdGen

  let range = (12,100) :: (Int, Int)

  let (r, g') = randomR range g

  print r
  print $ randomR range g
  print $ randomR range g

  print $ randomR range g'

  let (g2, g3) = split g'

  print $ randomR range g2
  print $ randomR range g3

  let ctx = defaultSIRCtx g
      ret = runTimeSIR ctx

  print $ last ret

  --let ret' = map (\(t, (s, i, r)) -> (t, (fromIntegral s, fromIntegral i, fromIntegral r))) retCompr
  --writeMatlabFile "sir-time.m" ret'
  --writeCSVFile "sir-time.csv" ret'