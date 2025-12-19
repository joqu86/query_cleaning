/****************************************************************************
Director Executive Dashboard
Sections:
	Permits
	Inspections
	Violations

Created Date: 12/02/2025
Created By: 
	Eli, Hannah (DOB) <hannah.eli@dc.gov>; 
	Eastlack, Aaron (DOB) <aaron.eastlack@dc.gov>; 
	Wenckowski, Emma (DOB) <emma.wenckowski@dc.gov>; 
	Oquendo, Julian (DOB) <julian.oquendo@dc.gov>; 
	Jayaraj Balraj <jayaraj.balraj@dc.gov>

Report Link:
******************************************************************************/
USE ODI_DB
/******************************************
Calendar Table
*******************************************/
/*
DROP TABLE IF EXISTS TABLEAU_EXEC_DASH_CALENDAR;
Create table TABLEAU_EXEC_DASH_CALENDAR
(
Load_Date						Datetime Not Null,
Month_EndDate_Key				Date Not Null,
Month_EndDate_PreviousMonth			Date Null,					
Month_EndDate_PreviousYearMonth		Date Null,
Fiscal_Year						Int  Null,
Fiscal_Quarter					Varchar(2) Null,	
Month_ShortName					Char(3),
Display_Name					Varchar(4),
Indicator_Latest_Month			Int,
Indicator_Previous_Month		Int,
Indicator_Previous_Year_Month	Int
)

create index idx0_Month_EndDate_Key on TABLEAU_EXEC_DASH_CALENDAR(Month_EndDate_Key);
create index idx1_Previous_MonthEndDate on TABLEAU_EXEC_DASH_CALENDAR(Month_EndDate_PreviousMonth,Month_EndDate_PreviousYearMonth);
create index idx2_Fiscal_Year on TABLEAU_EXEC_DASH_CALENDAR(Fiscal_Year,Display_Name);
create index idx3_Latest_Month_Indicator on TABLEAU_EXEC_DASH_CALENDAR(Indicator_Latest_Month);
*/

TRUNCATE TABLE TABLEAU_EXEC_DASH_CALENDAR;
INSERT INTO TABLEAU_EXEC_DASH_CALENDAR
SELECT 
	GETDATE()							AS	Load_Date,
	PKDATE								AS  Month_EndDate_Key,
	EOMONTH(PKDATE, -1)					AS	Month_EndDate_PreviousMonth,
	EOMONTH(DATEADD(YEAR,-1,PKDATE))	AS	Month_EndDate_PreviousYearMonth,
	FISCAL_YEAR,
	FISCAL_QUARTER,
	CALENDAR_MONTH_NAME_SHORT			AS	Month_ShortName,
	LEFT(CALENDAR_MONTH_NAME_SHORT,1) +'-'+RIGHT(CALENDAR_YEAR,2)		AS	Display_Name,
	CASE WHEN EOMONTH(PKDATE) = EOMONTH(GETDATE()) THEN 1 ELSE 0 END AS Indicator_Latest_Month,
	CASE WHEN EOMONTH(PKDATE) = EOMONTH(DATEADD(MONTH,-1,GETDATE())) THEN 1 ELSE 0 END AS Indicator_Previous_Month,
	CASE WHEN EOMONTH(PKDATE) = EOMONTH(DATEADD(YEAR,-1,GETDATE())) THEN 1 ELSE 0 END AS Indicator_Previous_Year_Month
FROM TBL_CALENDAR_FY
WHERE PKDATE = EOMONTH(PKDATE)
AND PKDATE >='2024-10-01' AND PKDATE <=EOMONTH(GETDATE()) 
;

--SELECT * FROM TABLEAU_EXEC_DASH_CALENDAR

/******************************************
Violations Table
*******************************************/
DROP TABLE IF EXISTS TABLEAU_EXEC_DASH_VIOLATIONS;
Create table TABLEAU_EXEC_DASH_VIOLATIONS
(
Load_Date						Datetime Not Null,
Month_EndDate_Key				Date Not Null,
Section							varchar(100),
Sub_Section						varchar(100),
Violation_Type					varchar(100),
[Filter_1]						varchar(100),
Measure_Type					varchar(100),
Measure_Values					decimal(9, 2),
Ward							varchar(100)


)

create index idx0_Month_EndDate_Key on TABLEAU_EXEC_DASH_VIOLATIONS(Month_EndDate_Key);
create index idx1_Filters on TABLEAU_EXEC_DASH_VIOLATIONS(Violation_Type, Filter_1, Ward);
create index idx2_Sections on TABLEAU_EXEC_DASH_VIOLATIONS(Section, Sub_Section);

/******************************************
Violations Abated 
Data will match Public Dashboard KPI
*******************************************/
SELECT *
INTO #Step1_Violation_Data
FROM
(
		SELECT 
			FY.FISCAL_YEAR,
			FY.FISCAL_QUARTER_CHAR_DESC		AS	FISCAL_QUARTER,
			A.*,
			CASE WHEN 
				(ABATEMENT_STATUS IN 
					('Abated','Abatement Post IR (INSP)','Abatement Post IR (NO INSP)','Abatement Post NOI-ART',
					'Abatement Post NOI-By DCRA','Abatement Post NOI-ICA (INSP)','Abatement Post NOI-ICA (NO INSP)','Abatement Post NOI-OCI',
					'Abatement Post NOI-OGC','Abated - Post NOI','No Violations Found') 
				AND 
				CAST([ABATED_DATE] AS DATE) <= CAST(TARGET_RESOLUTION_DATE AS DATE)) THEN 1 ELSE 0 END AS [SLA_MET_INDICATOR],
		EOMONTH(CAST(A.TARGET_RESOLUTION_DATE AS DATE))	AS	ABATED_MONTH
		FROM 
			(
				SELECT 
					[GROUP],
					CAP_ID,
					CAP_CREATED_DATE,
					CAP_ALIAS,
					CAP_STATUS,
					CAP_STATUS_DATE,
					SERVICE_STATUS,
					SERVICE_DATE,
					ABATEMENT_STATUS,
					ABATEMENT_STATUS_UPDATED_DATE	AS	[ABATED_DATE],
					[VIOLATION],
					v.[FULL_ADDRESS]				AS	[ADDRESS],
					[OWNER_FULLNAME]			AS	[OWNER_NAME],
					[ORIGINAL_FINE_AMOUNT]		AS	[FINE_AMOUNT],
					VIOLATION_RESPONSE_LEVEL,
					CASE WHEN VIOLATION_RESPONSE_LEVEL = 'Emergency' THEN DATEADD(DAY,30,SERVICE_DATE) ELSE DATEADD(DAY, 90, SERVICE_DATE)	END		AS	TARGET_RESOLUTION_DATE,
					o.WARD
					
				FROM 
				CPMS_REPOSITORY_CS.DBO.VIOLATION_LEVEL_ABATEMENT_TRACKING_OUTSTANDING v
				left join ODI_ADDRESS o ON v.CAP_ID=o.B1_ALT_ID 
				WHERE 
					SERVICE_STATUS IS NOT NULL
				AND [GROUP] IN ('Housing','Proactive')
				AND VIOLATION_RESPONSE_LEVEL IN ('Emergency', 'Routine')
				AND CAP_STATUS NOT IN ('Cancelled','Cancelled - Error','Cancelled - Refusing Entry','Cancelled-Administrative Error','Case Canceled','Case Cancelled')
			)AS	A
			LEFT OUTER JOIN
			ODI_DB.DBO.TBL_CALENDAR_FY FY
			ON CAST(A.TARGET_RESOLUTION_DATE AS DATE)= CAST(FY.PKDATE AS DATE)
)AS B
WHERE FISCAL_YEAR>=2024
--WHERE [SLA_MET_INDICATOR]=1
;

/*************************************************************
Vacant Properties Productive Use
*************************************************************/
SELECT	
	EOMONTH(CAST(UPDATE_DATE_TIME AS DATE))	AS	VACANTPROP_PRODUCTIVEUSE_MONTH,
	Record_Id,
	Workflow_Task,
	Workflow_Status,
	Workflow_Date_Time,
	Class_Id_From,
	Class_Id_To,
	Class,
	SSL_Info,
	Full_Address,
	Otr_Address,
	Registration_Start_Date,
	Registration_End_Date,
	Start_Year,
	Start_Half,
	End_Year,
	End_Half,
	Current_Otr_Class,
	Record_Date,
	Update_Type,
	Update_Status,
	Update_Date_Time,
	WARD

INTO #Step2_VP_PU
	FROM
		(
			SELECT * 
			FROM
				(
					SELECT 
						n.*,
						ROW_NUMBER()  OVER(PARTITION BY ssl_info ORDER BY RECORD_DATE DESC)				AS	LATEST_RECORD_ADDR,
						a.WARD
					FROM 
					[10.83.73.188].[PropertyManagementSystem].[dbo].[DCRA_CLASS_NOTICE] n
					left outer join (select distinct address_id, ward from ODI_DB.dbo.ODI_ADDRESS) a on n.OTR_Address=a.ADDRESS_ID
					WHERE 
						Workflow_Status in('Occupied per Inspection','Occupied Designation Approved','Occupied','Closed - Occupied')
					AND Update_Status='Success'
					AND Class_Id_From in('Class 3','Class 4')
					AND Class_Id_To in('Class 2','Class 1')
				)AS A 
			--WHERE LATEST_RECORD_ADDR = 1 
		)AS B
	LEFT OUTER JOIN
	DATA_STAGING_CS.DBO.TBL_ETL_OWNERPTS C
	ON 
		B.[SSL_info] = C.[SSL]
	WHERE 
		C.[DELCODE] <>'Y'

;--7642


/*********************************
Load data into Reporting Table
**********************************/
TRUNCATE TABLE TABLEAU_EXEC_DASH_VIOLATIONS;
--SUMMARY DATA
INSERT INTO TABLEAU_EXEC_DASH_VIOLATIONS
SELECT 
	GETDATE()						AS		Load_Date,
	ABATED_MONTH					AS		Month_EndDate_Key, 
	'Housing Code Violations'		AS		Section,
	'Summary'						AS		Sub_Section,
	VIOLATION_RESPONSE_LEVEL		AS		Violation_Type,
	[GROUP]							AS		[Filter_1],
	'Violations Abated'				AS		Measure_Type,
	COUNT(*)						AS		Measure_Values,
	WARD							AS		Ward
FROM #Step1_Violation_Data
GROUP BY 
	ABATED_MONTH
	,VIOLATION_RESPONSE_LEVEL
	,[GROUP]
	, WARD
;

--NOIE DATA
INSERT INTO TABLEAU_EXEC_DASH_VIOLATIONS
SELECT 
	GETDATE()						AS		Load_Date,
	ABATED_MONTH					AS		Month_EndDate_Key, 
	'Abatement Speed'				AS		Section,
	'Summary'						AS		Sub_Section,
	VIOLATION_RESPONSE_LEVEL		AS		Violation_Type,
	[GROUP]							AS		[Filter_1],
	'NOI-E Abated within 30 Days'	AS		Measure_Type,
	COUNT(*)						AS		Measure_Values,
	WARD							AS		Ward
FROM #Step1_Violation_Data
WHERE 
	VIOLATION_RESPONSE_LEVEL ='Emergency' AND [SLA_MET_INDICATOR]=1
GROUP BY ABATED_MONTH,VIOLATION_RESPONSE_LEVEL,[GROUP], WARD
;

--NOIR DATA
INSERT INTO TABLEAU_EXEC_DASH_VIOLATIONS
SELECT 
	GETDATE()						AS		Load_Date,
	ABATED_MONTH					AS		Month_EndDate_Key, 
	'Abatement Speed'				AS		Section,
	'Summary'						AS		Sub_Section,
	VIOLATION_RESPONSE_LEVEL		AS		Violation_Type,
	[GROUP]							AS		[Filter_1],
	'NOI-R Abated within 90 Days'	AS		Measure_Type,
	COUNT(*)						AS		Measure_Values,
	WARD							AS		Ward
FROM #Step1_Violation_Data
WHERE 
	VIOLATION_RESPONSE_LEVEL ='Routine' AND [SLA_MET_INDICATOR]=1
GROUP BY ABATED_MONTH,VIOLATION_RESPONSE_LEVEL,[GROUP], WARD
;

--Vacant Properties Returned to Productive Use data
INSERT INTO TABLEAU_EXEC_DASH_VIOLATIONS
SELECT 
	GETDATE()										AS		Load_Date,
	VACANTPROP_PRODUCTIVEUSE_MONTH					AS		Month_EndDate_Key, 
	'Housing Code Violations'						AS		Section,
	'Summary'										AS		Sub_Section,
	''												AS		Violation_Type,
	CASE 
		WHEN Class_Id_From='Class 3' Then 'Buildings'
		WHEN Class_Id_From='Class 4' Then 'Blighted'
	END 	AS		[Filter_1],
	'Vacant Properties Returned to Productive Use'	AS		Measure_Type,
	COUNT(*)										AS		Measure_Values,
	WARD											AS		Ward
FROM #Step2_VP_PU
GROUP BY VACANTPROP_PRODUCTIVEUSE_MONTH,Class_Id_From, WARD
;

DROP TABLE #Step1_Violation_Data;
DROP TABLE #Step2_VP_PU;


/**********************
Permit information 
From Emma Wenckowski 12/4/25
***********************/
drop table if exists TABLEAU_EXEC_DASH_PERMITS

Create table TABLEAU_EXEC_DASH_PERMITS
(
Load_Date					Datetime Not Null,
Month_EndDate_Key			Date Not Null,	
Section						Varchar(100),
Sub_Section					Varchar(100),
Job_Class					Varchar(100),
Permit_Types				Varchar(100),
Measure_Type				Varchar(100),
Measure_Values				Decimal(9,2),
Denominator					Decimal(9,2)
)

create index idx0_Month_EndDate_Key on TABLEAU_EXEC_DASH_PERMITS(Month_EndDate_Key);
create index idx1_Filters on TABLEAU_EXEC_DASH_PERMITS(Permit_Types,Job_Class);
create index idx2_Sections on TABLEAU_EXEC_DASH_PERMITS(Section,Sub_Section);


----Permits Data

TRUNCATE TABLE TABLEAU_EXEC_DASH_PERMITS;
with detailed_data as (
select 
EOMONTH(WF_PERMIT_ISSUED_DATE) AS [Month End Date Key],
DATEADD(DAY, 1, EOMONTH(WF_PERMIT_ISSUED_DATE, -1)) AS [Month Start Date Key],
CAP_ID, Job_Classification AS [Job Class], PERMIT_TYPE_ALIAS as [Permit Types], 
TotalDisciplineReviewCycles, BusinessDays_ActiveWFIApplUpload_PermitIssuedDate
-- if we want to add anything about DOB time or prescreens etc. that can be done here
--into #detailed_data
from ODI_DB.dbo.TABLEAU_ALL_PERMITS_ISSUED as p
left join ODI_DB.dbo.SS_CAP_APO as s
on s.B1_ALT_ID = p.CAP_ID
where p.WF_PERMIT_ISSUED_DATE > '10/01/22'
and PERMIT_TYPE = 'Construction'
),

applications as (
select 
EOMONTH(FlowTask_DateUpdated) AS [Month End Date Key],
DATEADD(DAY, 1, EOMONTH(FlowTask_DateUpdated, -1)) AS [Month Start Date Key],
Job_Class AS [Job Class], alias as [Permit Types], 
pdox_b1_id
--into #applications
from ODI_DB.dbo.STATIC_PDOX
where GroupName = 'Applicant'
and TaskName = 'ApplicantUpload'
and TaskStatus = 'Complete'
and FlowTask_DateUpdated > '10/01/22'
) 

INSERT INTO TABLEAU_EXEC_DASH_PERMITS

/****GRAPH DATA******/
select *
from (
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(cap_id) as [Measure Value],
0 as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Volume' as Section, 'Summary' as [Sub Section],
[Job Class], [Permit Types], 
'No of Permits Issued' as [Measure Type],
 CAP_ID
FROM detailed_data
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
) 

union

-- No of Permit Applications
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(pdox_b1_id) as [Measure Value],
0 as Denominator
from (
select [Month End Date Key], [Month Start Date Key],
'Permit Volume' as Section, 'Summary' as [Sub Section],
[Job Class], [Permit Types], 
'No of Permit Applications' as [Measure Type],
pdox_b1_id
from applications
) as u
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)

union

--Issued within 2 Review Cycles
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
sum(over_2_indic) as [Measure Value],
count(*) as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Summary' as [Sub Section],
[Job Class], [Permit Types], 
'Issued in 2 Review Cycles or Fewer' as [Measure Type],
case when TotalDisciplineReviewCycles <= 2 then 1 else 0 end as over_2_indic
FROM detailed_data
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)

union

--Total Time Issued
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
sum(BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) as [Measure Value],
count(*) as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Summary' as [Sub Section],
[Job Class], [Permit Types], 
'Total Business Days' as [Measure Type],
BusinessDays_ActiveWFIApplUpload_PermitIssuedDate
FROM detailed_data
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)

union 

--90% of permits issued within
(
select distinct getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Measure Value]
,COUNT (BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Denominator]
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Summary' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'90% Permits Issued Within' as [Measure Type],
BusinessDays_ActiveWFIApplUpload_PermitIssuedDate
FROM detailed_data
) as a
)



union

/***Large Commercial Construcction***/
/*************ADD ISSUED IN 2 CYCLES OR FEWER %*****************/

-- Permits Issued
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(cap_id) as [Measure Value],
0 as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Volume' as Section, 'Large Commercial Construction' as [Sub Section],
'' as [Job Class], '' as [Permit Types], 
'No of Permits Issued' as [Measure Type],
 CAP_ID
FROM detailed_data
where [Job Class] in ('AA-C','A-C','V-C') 
and [Permit Types] in ('Addition Alteration Repair Permit','Alteration and Repair Permit','New Building Permit')
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
) 

union 

-- No of Permit Applications
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(pdox_b1_id) as [Measure Value],
0 as Denominator
from (
select [Month End Date Key], [Month Start Date Key],
'Permit Volume' as Section, 'Large Commercial Construction' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'No of Permit Applications' as [Measure Type],
pdox_b1_id
from applications
where [Job Class] in ('AA-C','A-C','V-C') 
and [Permit Types] in ('Addition Alteration Repair Permit','Alteration and Repair Permit','New Building Permit')
) as u
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)

union

-- 90% of permits issued within...
(
select distinct getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Measure Value]
,COUNT (BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Denominator]
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Large Commercial Construction' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'90% Permits Issued Within' as [Measure Type],
BusinessDays_ActiveWFIApplUpload_PermitIssuedDate
FROM detailed_data
where [Job Class] in ('AA-C','A-C','V-C') 
and [Permit Types] in ('Addition Alteration Repair Permit','Alteration and Repair Permit','New Building Permit')
) as a
)

union

---issued in 2 cycles or fewer
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
sum(over_2_indic) as [Measure Value],
count(*) as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Large Commercial Construction' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'Issued in 2 Review Cycles or Fewer' as [Measure Type],
case when TotalDisciplineReviewCycles <= 2 then 1 else 0 end as over_2_indic
FROM detailed_data
where [Job Class] in ('AA-C','A-C','V-C') 
and [Permit Types] in ('Addition Alteration Repair Permit','Alteration and Repair Permit','New Building Permit')
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)


union
/***Danger Close***/
/*************ADD ISSUED IN 2 CYCLES OR FEWER %*****************/


-- Permits Issued
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(cap_id) as [Measure Value],
0 as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Volume' as Section, 'Danger Close' as [Sub Section],
'' as [Job Class], '' as [Permit Types], 
'No of Permits Issued' as [Measure Type],
 CAP_ID
FROM detailed_data
where [Job Class] in ('AA-C','A-C','V-C') 
and [Permit Types] in ('Alteration and Repair Permit', 'Addition Alteration Repair Permit','New Building Permit','Demolition Permit','Excavation Only Permit','Civil Plans','Historic Property - Special Permit',
	'Raze Permit','Retaining Wall Permit','Garage Permit','Foundation Only Permit') 
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
) 

union 

-- No of Permit Applications
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
count(pdox_b1_id) as [Measure Value],
0 as Denominator
from (
select [Month End Date Key], [Month Start Date Key],
'Permit Volume' as Section, 'Danger Close' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'No of Permit Applications' as [Measure Type],
pdox_b1_id
from applications
where [Permit Types] in ('Alteration and Repair Permit', 'Addition Alteration Repair Permit','New Building Permit','Demolition Permit','Excavation Only Permit','Civil Plans','Historic Property - Special Permit',
	'Raze Permit','Retaining Wall Permit','Garage Permit','Foundation Only Permit') 
) as u
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)

union

-- 90% of permits issued within...
(
select distinct getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Measure Value]
,COUNT (BusinessDays_ActiveWFIApplUpload_PermitIssuedDate) OVER (PARTITION BY [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]) AS [Denominator]
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Danger Close' as [Sub Section],
'' [Job Class], '' [Permit Types], 
'90% Permits Issued Within' as [Measure Type],
BusinessDays_ActiveWFIApplUpload_PermitIssuedDate
FROM detailed_data
where [Permit Types] in ('Alteration and Repair Permit', 'Addition Alteration Repair Permit','New Building Permit','Demolition Permit','Excavation Only Permit','Civil Plans','Historic Property - Special Permit',
	'Raze Permit','Retaining Wall Permit','Garage Permit','Foundation Only Permit') 
) as a
)

union

---issued in 2 cycles or fewer
(
select getdate() as [Load Date], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type],
sum(over_2_indic) as [Measure Value],
count(*) as Denominator
from (
SELECT [Month Start Date Key], [Month End Date Key],
'Permit Speed' as Section, 'Danger Close' as [Sub Section],
'' [Job Class], '' [Permit Types],  
'Issued in 2 Review Cycles or Fewer' as [Measure Type],
case when TotalDisciplineReviewCycles <= 2 then 1 else 0 end as over_2_indic
FROM detailed_data
where [Permit Types] in ('Alteration and Repair Permit', 'Addition Alteration Repair Permit','New Building Permit','Demolition Permit','Excavation Only Permit','Civil Plans','Historic Property - Special Permit',
	'Raze Permit','Retaining Wall Permit','Garage Permit','Foundation Only Permit') 
) as a
group by [Month Start Date Key], [Month End Date Key],Section, [Sub Section],
[Job Class], [Permit Types], [Measure Type]
)
) as g
--use ODI_DB;

--/**********************
--Inspection information 
--From Julian Oquendo 12/02/2025
--***********************/
DROP TABLE IF EXISTS TABLEAU_EXEC_DASH_INSPECTIONS
Create table TABLEAU_EXEC_DASH_INSPECTIONS
(
Load_Date					Datetime Not Null,
Month_EndDate_Key			Date Not Null,	
Section						Varchar(100),
Sub_Section					Varchar(100),
Inspection_Cap_Type			Varchar(100),
Inspection_Type				Varchar(100),
Measure_Type				Varchar(100),
Measure_Values				Decimal(9,2),
Denominator					Decimal(9,2),
Ward						Varchar(100)
)

create index idx0_Month_EndDate_Key on TABLEAU_EXEC_DASH_INSPECTIONS(Month_EndDate_Key);
create index idx1_Filters on TABLEAU_EXEC_DASH_INSPECTIONS(Inspection_Type,Inspection_Cap_Type, Ward);
create index idx2_Sections on TABLEAU_EXEC_DASH_INSPECTIONS(Section,Sub_Section);

--Inspections Data

TRUNCATE TABLE TABLEAU_EXEC_DASH_INSPECTIONS;

WITH inspections_base_table AS (
	SELECT 
		GETDATE() AS Load_Date,
		EOMONTH(COMPLETED_DATE) AS Month_EndDate_Key,
		[group] AS Inspection_Cap_Type,
		ACTION_TYPE AS Inspection_Type,
		CAP_ID,
		CAP_STATUS,
		CAP_STATUS_DATE,
		CAP_CREATEDATE,
		COMPLETED_DATE,
		G6_STATUS,
		ROW_NUMBER() OVER(PARTITION BY CAP_ID ORDER BY COMPLETED_DATE ASC) AS UNIQUE_RECORD,
		CASE WHEN ODI_DB.[dbo].[target_date] (cast(CAP_CREATEDATE as date), 10) >= COMPLETED_DATE THEN 1 ELSE 0 END AS SLA_MET,
		CASE WHEN CAP_STATUS LIKE 'NO ACCESS%' THEN 1 ELSE 0 END AS NO_ACCESS_FLAG,
		WARD

	FROM ODI_DB.dbo.TABLEAU_ICA_INSPECTIONS I
	WHERE COMPLETED_DATE >= '2022-10-01'
	AND STATUS_DES IN ('Completed')
	AND R3_DIVISION_CODE NOT IN ('3RDPARTY')
	AND (inspector_group NOT IN ('Historical', 'OIS', 'Third Party') OR inspector_group IS NULL)
)

INSERT INTO TABLEAU_EXEC_DASH_INSPECTIONS

-- Number of Inspections Completed
SELECT 
	Load_Date,
	Month_EndDate_Key,
	'Inspection Volume' AS Section,
	'Number of Inspections Completed' AS Sub_Section,
	Inspection_Cap_Type,
	Inspection_Type,
	'Number of Inspections Completed' AS Measure_Type,
	COUNT(*) AS Measure_Values,
	0 as Denominator,
	WARD as Ward

FROM inspections_base_table
WHERE CAP_STATUS NOT LIKE 'NO ACCESS%'
GROUP BY 
	Load_Date,
	Month_EndDate_Key,
	Inspection_Cap_Type,
	Inspection_Type,
	WARD

UNION ALL

-- Percent No Access Result
SELECT 
	Load_Date,
	Month_EndDate_Key,
	'Inspection Volume' AS Section,
	'Percent No Access Result' AS Sub_Section,
	Inspection_Cap_Type,
	Inspection_Type,
	'Percent No Access' AS Measure_Type,
	SUM(NO_ACCESS_FLAG) AS Measure_Values,
	COUNT(*) AS Denominator,
	WARD as Ward
FROM inspections_base_table
GROUP BY 
	Load_Date,
	Month_EndDate_Key,
	Inspection_Cap_Type,
	Inspection_Type,
	WARD

UNION ALL

-- Taking Place in 10 Business Days (Housing only)
SELECT 
	Load_Date,
	Month_EndDate_Key,
	'Inspection Speed' AS Section,
	'Taking Place in 10 Business Days' AS Sub_Section,
	Inspection_Cap_Type,
	Inspection_Type,
	'Number of 10 Day Completion Inspections' AS Measure_Type,
	SUM(SLA_MET) AS Measure_Values,
	COUNT(*) AS Denominator,
	WARD as Ward
FROM inspections_base_table
WHERE UNIQUE_RECORD = 1 
AND Inspection_Cap_Type = 'Housing'
GROUP BY 
	Load_Date,
	Month_EndDate_Key,
	Inspection_Cap_Type,
	Inspection_Type,
	WARD

UNION ALL


-- Ask Hannah whether it makes sense to use 90th percentile as a DYNAMIC value, or use average instead. 
-- 90th Percentile (Housing only)
SELECT DISTINCT
	Load_Date,
	Month_EndDate_Key,
	'Inspection Speed' AS Section,
	'90th Percentile' AS Sub_Section,
	Inspection_Cap_Type,
	Inspection_Type,
	'90th Percentile' AS Measure_Type,
	PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY business_days_to_complete) OVER (PARTITION BY Month_EndDate_Key, Inspection_Cap_Type, Inspection_Type) AS Measure_Values,
	0 AS Denominator,
	WARD as Ward
FROM (
	SELECT 
		Load_Date,
		Month_EndDate_Key,
		Inspection_Cap_Type,
		CASE WHEN Inspection_Type IN ('Follow Up Inspection', 'Follow-Up Inspection') THEN 'Follow-Up Inspection' ELSE Inspection_Type END AS Inspection_Type,
		(DATEDIFF(dd, CAP_CREATEDATE, COMPLETED_DATE))
			- (DATEDIFF(wk, CAP_CREATEDATE, COMPLETED_DATE) * 2)
			- (CASE WHEN DATENAME(dw, CAP_CREATEDATE) = 'Sunday' THEN 1 ELSE 0 END)
			- (CASE WHEN DATENAME(dw, COMPLETED_DATE) = 'Saturday' THEN 1 ELSE 0 END) AS business_days_to_complete,
		WARD
	FROM inspections_base_table
	WHERE Inspection_Cap_Type = 'Housing'
) AS T