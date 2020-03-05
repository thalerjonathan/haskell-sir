-- :m Test.QuickCheck
-- :! clear
import Test.QuickCheck









prop_reverse_reverse :: [Int] -> Bool
prop_reverse_reverse xs 
  = reverse (reverse xs) == xs

prop_reverse_dist :: [Int] -> [Int] -> Bool
prop_reverse_dist xs ys 
  = reverse (xs ++ ys) == reverse ys ++ reverse xs







prop_ass_float :: Float -> Float -> Float -> Bool
prop_ass_float x y z 
  = (x + y) + z == x + (y + z)

prop_ass_int :: Int -> Int -> Int -> Bool
prop_ass_int x y z
  = (x + y) + z == x + (y + z)







prop_reverse_coverage :: [Int] -> Property
prop_reverse_coverage xs 
    = checkCoverage $ cover 
        100 
        (length xs >= 50) 
        "lists at least 50 elements"
        (reverse (reverse xs) == xs)