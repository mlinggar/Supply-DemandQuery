-- Supply

SELECT  CAST(supplydata.Time AS TIME) As Time, ROUND(AVG(supplydata.[Online (h)]*60), 0) AS SupplyNumberPerMin
FROM Bolt.dbo.['Supply Data$'] AS supplydata
INNER JOIN Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
ON supplydata.Date = demanddata.Date AND supplydata.Time = demanddata.Time
GROUP BY CAST(CONVERT(TIME, supplydata.Time) AS Time) 
ORDER BY 1 ASC

-- 24-hour curve of average demand and supply volume (to illustrate if there is any match/mismatch)

DROP TABLE IF exists #HourlySupplyDemand
CREATE TABLE #HourlySupplyDemand
(
Time TIME,
SupplyNumberPerMin FLOAT,
DemandNumPerMin FLOAT,
);

WITH AVGDur AS
( 
SELECT AVG((supplydata.[Has booking (h)]*60) / NULLIF(supplydata.[Finished Rides],0)) AS AVGRideDuration
FROM Bolt.dbo.['Supply Data$'] supplydata
INNER JOIN Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
ON supplydata.Date = demanddata.Date AND supplydata.Time = demanddata.Time
),

DemandHour AS 
(
SELECT demanddata.Time AS DemandHour
FROM Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
),

AVGDurPerHour AS (
SELECT DemandHour, AVGRideDuration
FROM DemandHour 
CROSS JOIN AVGDur
),

DemandNum AS (
SELECT CAST(demanddata.Time AS TIME) AS Time, ROUND(AVG((demanddata.[People saw 0 cars (unique)] + demanddata.[People saw +1 cars (unique)]) * AVGDurPerHour.AVGRideDuration), 0) AS DemandNumPerMin
FROM  Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
INNER JOIN AVGDurPerHour
ON demanddata.Time = AVGDurPerHour.DemandHour
GROUP BY CAST(CONVERT(TIME, demanddata.Time) AS Time) 
),

SupplyNum AS (
SELECT  CAST(supplydata.Time AS TIME) As Time, ROUND(AVG(supplydata.[Online (h)]*60), 0) AS SupplyNumberPerMin
FROM Bolt.dbo.['Supply Data$'] AS supplydata
INNER JOIN Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
ON supplydata.Date = demanddata.Date AND supplydata.Time = demanddata.Time
GROUP BY CAST(CONVERT(TIME, supplydata.Time) AS Time) 
)
INSERT INTO #HourlySupplyDemand
SELECT SupplyNum.Time, SupplyNum.SupplyNumberPerMin, DemandNum.DemandNumPerMin
FROM SupplyNum
INNER JOIN DemandNum
ON SupplyNum.Time = DemandNum.Time


SELECT *
FROM #HourlySupplyDemand
ORDER BY 1 DESC

-- Undersupplied hours during a weekly period (Monday to Sunday) so that we can send to drivers and inform them when to be online for extra hours

DROP TABLE IF exists #DailySupplyDemand
CREATE TABLE #DailySupplyDemand
(
Day INT,
Time TIME,
SupplyNumberPerMin FLOAT,
DemandNumPerMin FLOAT,
);
WITH AVGDur AS
( 
SELECT AVG((supplydata.[Has booking (h)]*60) / NULLIF(supplydata.[Finished Rides],0)) AS AVGRideDuration
FROM Bolt.dbo.['Supply Data$'] supplydata
INNER JOIN Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
ON supplydata.Date = demanddata.Date AND supplydata.Time = demanddata.Time
),

DemandHour AS 
(
SELECT demanddata.Time AS DemandHour
FROM Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
),

AVGDurPerHour AS (
SELECT DemandHour, AVGRideDuration
FROM DemandHour 
CROSS JOIN AVGDur
),

DemandNum AS (
SELECT CAST(demanddata.Time AS TIME) AS Time, ROUND(AVG((demanddata.[People saw 0 cars (unique)] + demanddata.[People saw +1 cars (unique)]) * AVGDurPerHour.AVGRideDuration), 0) AS DemandNumPerMin
FROM  Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
INNER JOIN AVGDurPerHour
ON demanddata.Time = AVGDurPerHour.DemandHour
GROUP BY CAST(CONVERT(TIME, demanddata.Time) AS Time) 
),

SupplyNum AS (
SELECT  DATEPART(dw, demanddata.date) AS Day, CAST(supplydata.Time AS TIME) As Time, ROUND(AVG(supplydata.[Online (h)]*60), 0) AS SupplyNumberPerMin
FROM Bolt.dbo.['Supply Data$'] AS supplydata
INNER JOIN Bolt.dbo.Hourly_OverviewSearch_1#csv$ AS demanddata
ON supplydata.Date = demanddata.Date AND supplydata.Time = demanddata.Time
GROUP BY CAST(CONVERT(TIME, supplydata.Time) AS Time), DATEPART(dw, demanddata.date)
)
INSERT INTO #DailySupplyDemand
SELECT SupplyNum.Day, SupplyNum.Time, SupplyNum.SupplyNumberPerMin, DemandNum.DemandNumPerMin
FROM SupplyNum
INNER JOIN DemandNum
ON SupplyNum.Time = DemandNum.Time

SELECT *
FROM #DailySupplyDemand
ORDER BY 1 DESC

--Supply Demand Table

SELECT Time, SupplyNumberPerMin, DemandNumPerMin
FROM #HourlySupplyDemand
ORDER BY 1 DESC

SELECT Day, Time, SupplyNumberPerMin, DemandNumPerMin
FROM #DailySupplyDemand
ORDER BY 1 DESC

-- Calculate the number of online hours required to ensure that we have a good Coverage Ratio during the peak hours you identified above.


SELECT Day, Time, SupplyNumberPerMin, DemandNumPerMin, ROUND(SupplyNumberPerMin/DemandNumPerMin*100, 0) AS SupplyRatio
FROM #DailySupplyDemand
ORDER BY 1, 2 DESC

SELECT Day, Time, SupplyNumberPerMin, DemandNumPerMin, ROUND(SupplyNumberPerMin/DemandNumPerMin*100, 0) AS SupplyRatio
FROM #DailySupplyDemand
WHERE ROUND(SupplyNumberPerMin/DemandNumPerMin*100, 0) < 100
ORDER BY 1, 2 DESC

SELECT Day, Time, SupplyNumberPerMin, DemandNumPerMin, ABS(ROUND((DemandNumPerMin-SupplyNumberPerMin)/60, 0)) AS OnlineHourRequired
FROM #DailySupplyDemand
WHERE Time = '09:00:00' OR Time BETWEEN '18:00:00' AND '19:00:00'
ORDER BY 1, 2 DESC





-- During peak hours, we can guarantee the drivers a certain amount of income. If the drivers make less than the guaranteed amount, we will pay them the difference. Please calculate how much earning we can guarantee so that we can attract more supply. Please explain your reasonings and you can assume the following:
-- Finished Rides have an average value of €10 (80% goes to drivers, 20% is our revenue)
-- With extra online hours available we will be able to capture the "missed coverage", i.e. "People saw 0 cars" in the demand sample data
DROP TABLE IF exists #MissCoverageHour
CREATE TABLE #MissCoverageHour
(
Day INT,
Time TIME,
MissedCoverage FLOAT,
MisscoverageHour FLOAT,
);
INSERT INTO #MissCoverageHour
SELECT Day, Time, DemandNumPerMin-SupplyNumberPerMin AS MissedCoverage,  ROUND((DemandNumPerMin-SupplyNumberPerMin)/60,0) AS MisscoverageHour
FROM #DailySupplyDemand
WHERE Time = '09:00:00' OR Time BETWEEN '18:00:00' AND '19:00:00'
ORDER BY 4 DESC

SELECT *
FROM #MissCoverageHour
ORDER BY MisscoverageHour DESC

SELECT DATEPART(dw, date) AS Day, CAST(Time AS TIME) As Time, [Rides per online hour] ,[Finished Rides], [Finished Rides] * 8 AS TotalDriverIncome, ROUND(([Finished Rides] * 8) * [Rides per online hour],2) AS IncomePerOnlineHour
FROM Bolt.dbo.['Supply Data$']



-- Total Earning

WITH AVGIncomePerOnlineHour AS (
SELECT ROUND(AVG(ROUND(([Finished Rides] * 10) * [Rides per online hour] / [Active drivers],0)), 0) AS AVGIncomePerOnlineHour
FROM Bolt.dbo.['Supply Data$']
),
AVGUnderSupplyHour AS (
SELECT ROUND(AVG(MisscoverageHour), 0) AS UnderSupplyHour
FROM #MissCoverageHour
)
SELECT ROUND(AVGIncomePerOnlineHour * UnderSupplyHour, 0) AS EarningGuaranted
FROM AVGIncomePerOnlineHour
CROSS JOIN AVGUnderSupplyHour


-- Table Miss Coverage with IncomePerHour

WITH MisscoverageHour AS (
SELECT Day, Time, SupplyNumberPerMin, DemandNumPerMin, DemandNumPerMin-SupplyNumberPerMin AS MissedCoverage,  ROUND((DemandNumPerMin-SupplyNumberPerMin)/60,0) AS MisscoverageHour
FROM #DailySupplyDemand
WHERE DemandNumPerMin > SupplyNumberPerMin
),

IncomePerOnlineHour AS(
SELECT DATEPART(dw, date) AS Day, CAST(Time AS TIME) As Time, SUM([Finished Rides]) AS FinishedRides, ROUND(SUM([Finished Rides] * 10),0) AS TotalDriverIncomePerHour, ROUND(AVG(ROUND(([Finished Rides] * 10) * [Rides per online hour],2)),0) AS IncomePerOnlineHour
FROM Bolt.dbo.['Supply Data$']
GROUP BY  DATEPART(dw, date), CAST(CONVERT(TIME, Time) AS Time)
)

SELECT TOP 10 MisscoverageHour.Day, MisscoverageHour.Time, MisscoverageHour.MissedCoverage , IncomePerOnlineHour.IncomePerOnlineHour
FROM MisscoverageHour
INNER JOIN IncomePerOnlineHour
ON MisscoverageHour.Day = IncomePerOnlineHour.Day AND MisscoverageHour.Time = IncomePerOnlineHour.Time
ORDER BY 3 DESC

SELECT *
FROM Bolt.dbo.['Supply Data$']