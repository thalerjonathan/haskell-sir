module Export.Matlab 
  ( writeMatlabFile
  ) where

import System.IO
import Text.Printf

writeMatlabFile :: String -> [(Double, (Double, Double, Double))] -> IO ()
writeMatlabFile fileName dynamics = do
  fileHdl <- openFile fileName WriteMode
  hPutStrLn fileHdl "dynamics = ["
  mapM_ (hPutStrLn fileHdl . sirDynamicToString) dynamics
  hPutStrLn fileHdl "];"

  hPutStrLn fileHdl "indices = dynamics (:, 1);"
  hPutStrLn fileHdl "susceptible = dynamics (:, 2);"
  hPutStrLn fileHdl "infected = dynamics (:, 3);"
  hPutStrLn fileHdl "recovered = dynamics (:, 4);"
  hPutStrLn fileHdl "totalPopulation = susceptible(1) + infected(1) + recovered(1);"

  hPutStrLn fileHdl "susceptibleRatio = susceptible ./ totalPopulation;"
  hPutStrLn fileHdl "infectedRatio = infected ./ totalPopulation;"
  hPutStrLn fileHdl "recoveredRatio = recovered ./ totalPopulation;"

  hPutStrLn fileHdl "figure"
  hPutStrLn fileHdl "plot (indices, susceptibleRatio.', 'color', 'blue', 'linewidth', 2);"
  hPutStrLn fileHdl "hold on"
  hPutStrLn fileHdl "plot (indices, infectedRatio.', 'color', 'red', 'linewidth', 2);"
  hPutStrLn fileHdl "hold on"
  hPutStrLn fileHdl "plot (indices, recoveredRatio.', 'color', 'green', 'linewidth', 2);"

  hPutStrLn fileHdl "set(gca,'YTick',0:0.05:1.0);"
  
  hPutStrLn fileHdl "xlabel ('Time');"
  hPutStrLn fileHdl "ylabel ('Population Ratio');"
  hPutStrLn fileHdl "legend('Susceptible','Infected', 'Recovered');"

  hClose fileHdl

sirDynamicToString :: (Double, (Double, Double, Double)) -> String
sirDynamicToString (t, (s, i, r)) =
  printf "%f" t ++
  "," ++ printf "%f" s ++
  "," ++ printf "%f" i ++ 
  "," ++ printf "%f" r ++
  ";"
