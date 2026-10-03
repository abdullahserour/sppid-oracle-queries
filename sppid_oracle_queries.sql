/* =============================================================================
   SPPID (SmartPlant P&ID) - Useful Oracle / SQL Queries
   -----------------------------------------------------------------------------
   All schema names, IDs, drawing numbers and tags below are FAKE placeholders.
     DEMO_PID                    -> your SPPID database schema (owner)
     DEMO-DWG-001, ...           -> drawing names / numbers
     <SOME_ID_PLACEHOLDER>       -> a 32-character SP_ID (GUID) from your own database

   WARNING
   - UPDATE / DELETE statements change SPPID data directly. Run them on a
     backup or test schema first, take a backup, and check the row count
     with a SELECT before you commit.
   - Table structures can differ between SPPID versions. Verify column names
     and code values (item status, component types) in your own environment.
   ============================================================================= */


/* =============================================================================
   A. BULK DATA CORRECTIONS
   ============================================================================= */

/* A1. Move pipe runs in specific drawings to another plant group (unit) */
UPDATE DEMO_PID.T_PlantItem
SET SP_PlantGroupID = '<TARGET_PLANT_GROUP_ID>'
WHERE SP_ID IN (
    SELECT PI.SP_ID
    FROM DEMO_PID.T_PipeRun PR
    JOIN DEMO_PID.T_PlantItem PI     ON PI.SP_ID = PR.SP_ID
    JOIN DEMO_PID.T_ModelItem M      ON M.SP_ID = PI.SP_ID
    JOIN DEMO_PID.T_Representation R ON R.SP_ModelItemID = M.SP_ID
    JOIN DEMO_PID.T_Drawing D        ON D.SP_ID = R.SP_DrawingID
    WHERE D.Name IN ('DEMO-DWG-001', 'DEMO-DWG-002')
);


/* A2. Move ALL plant items in the drawings of one unit to another plant group,
       selecting the drawings by the plant group they currently belong to */
UPDATE DEMO_PID.T_PlantItem
SET SP_PlantGroupID = '<TARGET_PLANT_GROUP_ID>'
WHERE SP_ID IN (
    SELECT PI.SP_ID
    FROM DEMO_PID.T_PlantItem PI
    JOIN DEMO_PID.T_ModelItem M      ON M.SP_ID = PI.SP_ID
    JOIN DEMO_PID.T_Representation R ON R.SP_ModelItemID = M.SP_ID
    JOIN DEMO_PID.T_Drawing D        ON D.SP_ID = R.SP_DrawingID
    WHERE D.SP_PlantGroupID IN ('<SOURCE_UNIT_PLANT_GROUP_ID>')
);


/* A3. Pad the tag sequence number of instruments with leading zeros
       (here to 5 digits - change the 5 to 6 for six digits).
       Choose ONE filter: by drawing names, or by the drawing's plant group.
       Optional lines let you exclude drawings. */
UPDATE DEMO_PID.T_Instrument
SET TagSequenceNo = LPAD(TagSequenceNo, 5, '0')
WHERE SP_ID IN (
    SELECT INS.SP_ID
    FROM DEMO_PID.T_PlantItem PI
    JOIN DEMO_PID.T_ModelItem M      ON M.SP_ID = PI.SP_ID
    JOIN DEMO_PID.T_Representation R ON R.SP_ModelItemID = M.SP_ID
    JOIN DEMO_PID.T_Drawing D        ON D.SP_ID = R.SP_DrawingID
    JOIN DEMO_PID.T_Instrument INS   ON INS.SP_ID = PI.SP_ID
    -- Option 1: by drawing names
    WHERE D.Name IN ('DEMO-DWG-001', 'DEMO-DWG-002')
    -- Option 2: by plant group (unit)
    -- WHERE D.SP_PlantGroupID = '<UNIT_PLANT_GROUP_ID>'
    -- Optional exclusions:
    -- AND D.Name NOT LIKE 'XX%'
    -- AND D.Name <> 'DEMO-DWG-900'
);


/* A4. Bulk update the tag sequence number of pipe runs from a mapping table
       (for example an Excel sheet imported as sheet1$ with columns [old tag], [new tag]).
       NOTE: this is SQL Server syntax. Use INNER JOIN, so unmatched rows keep their value
       (a LEFT JOIN would set unmatched pipe runs to NULL). */
UPDATE p
SET p.TagSequenceNo = s.[new tag]
FROM DEMO_PID.T_PipeRun p
INNER JOIN sheet1$ s ON p.TagSequenceNo = s.[old tag];


/* A5. Update PipelineFrom / PipelineTo of pipe runs from a staging table.
       Step 1 - preview the current values for one drawing. */
SELECT SP_ID, ItemTag, Name, PipelineFrom, PipelineTo
FROM (
    SELECT PR.SP_ID, PI.ItemTag, D.Name, PR.PipelineFrom, PR.PipelineTo,
           ROW_NUMBER() OVER (PARTITION BY PR.SP_ID ORDER BY PI.ItemTag) AS rn
    FROM DEMO_PID.T_PlantItem PI
    JOIN DEMO_PID.T_ModelItem M      ON M.SP_ID = PI.SP_ID
    JOIN DEMO_PID.T_Representation R ON R.SP_ModelItemID = M.SP_ID
    JOIN DEMO_PID.T_Drawing D        ON D.SP_ID = R.SP_DrawingID
    JOIN DEMO_PID.T_PipeRun PR       ON PR.SP_ID = PI.SP_ID
    WHERE D.Name = 'DEMO-DWG-001'
      AND PI.ItemTag IS NOT NULL
)
WHERE rn = 1
ORDER BY ItemTag;

/* Step 2 - update from the staging table (keyed by SP_ID).
   Only rows that exist in the staging table are changed. */
UPDATE DEMO_PID.T_PipeRun PR
SET (PR.PipelineFrom, PR.PipelineTo) = (
    SELECT S.PipelineFrom, S.PipelineTo
    FROM pipeline_staging S
    WHERE S.SP_ID = PR.SP_ID
)
WHERE EXISTS (SELECT 1 FROM pipeline_staging S WHERE S.SP_ID = PR.SP_ID);

/* Step 3 - check */
SELECT COUNT(*) FROM DEMO_PID.T_PipeRun
WHERE PipelineFrom IS NOT NULL OR PipelineTo IS NOT NULL;


/* A6. Bulk update process case values (e.g. design pressure) from an Excel sheet.
       Useful when the process team sends an updated Line List.
       Import the sheet into a table first (excel_caseprocess_update), with the
       columns ItemTag, MAX_DESIGN_PRESSURE and MAX_DESIGN_PRESSURE_SI. */
MERGE INTO DEMO_PID.T_CaseProcess cp
USING (
    SELECT c.SP_ID AS case_id,
           x.MAX_DESIGN_PRESSURE,
           x.MAX_DESIGN_PRESSURE_SI
    FROM excel_caseprocess_update x
    JOIN DEMO_PID.T_PlantItem pi ON pi.ItemTag = x.ItemTag
    JOIN DEMO_PID.T_ModelItem m  ON m.SP_ID = pi.SP_ID
    JOIN DEMO_PID.T_Case c       ON c.SP_ModelItemID = m.SP_ID
    WHERE c.CaseType = 1
) src
ON (cp.SP_CaseID = src.case_id AND cp.Quality = 2)
WHEN MATCHED THEN UPDATE SET
    cp.Pressure      = src.MAX_DESIGN_PRESSURE,
    cp.SP_PressureSI = src.MAX_DESIGN_PRESSURE_SI;

/* Check the result for one item */
SELECT pi.SP_ID, pi.ItemTag, cp.Pressure
FROM DEMO_PID.T_PlantItem pi
JOIN DEMO_PID.T_ModelItem m   ON m.SP_ID = pi.SP_ID
JOIN DEMO_PID.T_Case c        ON c.SP_ModelItemID = m.SP_ID
JOIN DEMO_PID.T_CaseProcess cp ON cp.SP_CaseID = c.SP_ID
WHERE pi.ItemTag = '<ITEM_TAG>'
  AND c.CaseType = 1
  AND cp.Quality = 2;


/* A7. Replace standard in-line piping components by specialty components
       (change type + symbol file). Example for gate valves.
       Repeat the pair of statements for each valve type, changing the symbol file
       and the PipingCompType code. Check the codes in your own code list. */
UPDATE DEMO_PID.T_PipingComp
SET PipingCompType = 10043,          -- code of the specialty gate valve in YOUR code list
    PipingCompSubclass = 7,
    SP_IsSpecialtyItem = 2
WHERE SP_ID IN (
    SELECT pc.SP_ID
    FROM DEMO_PID.T_PipingComp pc
    JOIN DEMO_PID.T_Representation r ON r.SP_ModelItemID = pc.SP_ID
    JOIN DEMO_PID.T_InlineComp ic    ON ic.SP_PipingCompID = pc.SP_ID
    WHERE r.FileName = '\Piping\Valves\2 Way Common\Gate Valve.sym'
      AND ic.SpCompPrfx = 1
);

UPDATE DEMO_PID.T_Representation
SET FileName = '\Piping\Specialty Components\Misc\Custom Specialty Gate Valve.sym'
WHERE SP_ModelItemID IN (
    SELECT r.SP_ModelItemID
    FROM DEMO_PID.T_PipingComp pc
    JOIN DEMO_PID.T_Representation r ON r.SP_ModelItemID = pc.SP_ID
    JOIN DEMO_PID.T_InlineComp ic    ON ic.SP_PipingCompID = pc.SP_ID
    WHERE r.FileName = '\Piping\Valves\2 Way Common\Gate Valve.sym'
      AND ic.SpCompPrfx = 1
);
-- Run the component-type update FIRST and the symbol update SECOND. Both find the
-- items through the OLD symbol file name, so once the symbol file is changed the
-- first statement would no longer find them.


/* A8. Rename a drawing (drawing number + name + path) in all three drawing tables */
UPDATE DEMO_PID.T_DrawingSite s
SET s.DrawingNumber = 'NEW-DWG-001', s.Name = 'NEW-DWG-001'
WHERE s.DrawingNumber = 'OLD-DWG-001';

UPDATE DEMO_PID.T_Drawing d
SET d.DrawingNumber = 'NEW-DWG-001', d.Name = 'NEW-DWG-001',
    d.Path = REPLACE(d.Path, 'OLD', 'NEW')
WHERE d.DrawingNumber = 'OLD-DWG-001';      -- do not forget this WHERE: without it every drawing is renamed

UPDATE DEMO_PID.T_GlobalDrawing g
SET g.DrawingNumber = 'NEW-DWG-001', g.Name = 'NEW-DWG-001'
WHERE g.DrawingNumber = 'OLD-DWG-001';


/* A9. Remove the second dash from all drawing numbers (e.g. AB-123-001 -> AB-123001)
       REGEXP_REPLACE(text, '(-)', '', 1, 2):
         '(-)' = match a dash | '' = replace with nothing
         1 = start from the first character | 2 = replace only the 2nd match */
UPDATE DEMO_PID.T_Drawing        SET DrawingNumber = REGEXP_REPLACE(DrawingNumber, '(-)', '', 1, 2);
UPDATE DEMO_PID.T_GlobalDrawing  SET DrawingNumber = REGEXP_REPLACE(DrawingNumber, '(-)', '', 1, 2);
UPDATE DEMO_PID.T_DrawingSite    SET DrawingNumber = REGEXP_REPLACE(DrawingNumber, '(-)', '', 1, 2);


/* A10. Replace the title block symbol in all drawings with another title block symbol */
UPDATE DEMO_PID.T_Representation
SET FileName = '\Design\Company_Title_Block.sym'
WHERE RepresentationType = 12
  AND FileName = '\Design\Company_Title_Block_Alternate.sym';


/* A11. Set inconsistencies of specific drawings to "approved" (IsApproved = 2) */
UPDATE DEMO_PID.T_Inconsistency i
SET IsApproved = 2
WHERE i.SP_RelationshipID IN (
    SELECT r.SP_ID
    FROM DEMO_PID.T_Relationship r
    WHERE r.SP_DrawingID IN ('<DRAWING_ID_1>', '<DRAWING_ID_2>', '<DRAWING_ID_3>')
);


/* =============================================================================
   B. CLEAN-UP OF BAD OR ORPHANED DATA
   ============================================================================= */

/* B1. Find stockpile representations that have no graphic (no graphic OID) */
SELECT R.SP_ID, R.SP_ModelItemID
FROM DEMO_PID.T_Representation R, DEMO_PID.T_PlantItem P, DEMO_PID.T_Drawing D
WHERE R.SP_ModelItemID = P.SP_ID(+)
  AND R.SP_DrawingID   = D.SP_ID(+)
  AND R.InStockpile = 1
  AND (
        ((R.GraphicOID IS NULL OR R.GraphicOID = 0) AND P.SP_RelationImpliedID IS NULL)
     OR (R.GraphicOID IS NULL AND P.SP_RelationImpliedID = 0)
      )
ORDER BY D.Name;


/* B2. Flag a bad item as deleted (ItemStatus = 4 is the value used in my workflow -
       verify in your environment). Do this per item, representation + model item.
       Step 1 - look at the representations of the items first */
SELECT *
FROM DEMO_PID.T_Representation
WHERE SP_ModelItemID IN ('<MODEL_ITEM_ID_1>', '<MODEL_ITEM_ID_2>');

/* Step 2 - flag them. Only run this after B1 shows no representation left
   that has a model item you still need. */
UPDATE DEMO_PID.T_Representation
SET ItemStatus = 4
WHERE SP_ID = '<REPRESENTATION_ID>'
  AND SP_ModelItemID = '<MODEL_ITEM_ID>'
  AND SP_DrawingID = '<DRAWING_ID>';          -- optional extra safety

UPDATE DEMO_PID.T_ModelItem
SET ItemStatus = 4
WHERE SP_ID = '<MODEL_ITEM_ID>';


/* B3. Investigate bad connectors: connectors with no connected items and fewer than 2 vertices */
SELECT C.SP_ID, D.Name
FROM DEMO_PID.T_Connector C
JOIN DEMO_PID.T_Representation R ON C.SP_ID = R.SP_ID
JOIN DEMO_PID.T_Drawing D        ON R.SP_DrawingID = D.SP_ID
WHERE C.SP_ConnectItem1ID IS NULL
  AND C.SP_ConnectItem2ID IS NULL
  AND R.ItemStatus = 1
  AND D.ItemStatus = 1
  AND (SELECT COUNT(*) FROM DEMO_PID.T_ConnectorVertex V WHERE V.SP_ConnectorID = C.SP_ID) < 2
ORDER BY D.Name;


/* B4. Find graphic OIDs that are used in more than one drawing, and duplicate
       representations of the same graphic inside one drawing */
SELECT GraphicOID,
       COUNT(DISTINCT SP_DrawingID) AS DRAWING_COUNT,
       LISTAGG(SP_DrawingID, ', ')  WITHIN GROUP (ORDER BY SP_DrawingID) AS AFFECTED_DRAWINGS,
       LISTAGG(SP_ModelItemID, ', ') WITHIN GROUP (ORDER BY SP_ModelItemID) AS AFFECTED_MODEL_ITEMS
FROM DEMO_PID.T_Representation
WHERE GraphicOID IS NOT NULL AND ItemStatus = 1 AND InStockpile = 1
GROUP BY GraphicOID
HAVING COUNT(DISTINCT SP_DrawingID) > 1;

SELECT GraphicOID, SP_DrawingID, COUNT(*)
FROM DEMO_PID.T_Representation
WHERE InStockpile = 1
GROUP BY GraphicOID, SP_DrawingID
HAVING COUNT(*) > 1;


/* B5. Label bug: count label records that are inconsistent */
SELECT COUNT(*)
FROM DEMO_PID.T_LabelPersist
WHERE (SP_RepresentationID IS NULL     AND LabelType > 1)
   OR (SP_RepresentationID IS NOT NULL AND LabelType = 1);


/* B6. Connector item bug: connectors whose connected symbol is drawn in a different drawing */
SELECT r.SP_ModelItemID
FROM DEMO_PID.T_Connector c, DEMO_PID.T_Representation r, DEMO_PID.T_Symbol s,
     DEMO_PID.T_Drawing d, DEMO_PID.T_Representation r1
WHERE c.SP_ID = r.SP_ID
  AND r.SP_DrawingID = d.SP_ID
  AND d.Name = 'DEMO-DWG-001'
  AND c.SP_ConnectItem1ID = s.SP_ID
  AND r1.SP_ID = s.SP_ID
  AND r1.SP_DrawingID <> r.SP_DrawingID;


/* B7. Corrupted SmartFrame: find it, delete the row, then remove orphaned storage records.
       Step 1 - list the SmartFrame rows of the drawing; check the SP_FileName column
       and compare with the corrupted .tmp file named in the SmartPlant P&ID log. */
SELECT *
FROM DEMO_PID.T_SmartFrame
WHERE SP_DrawingID IN (SELECT SP_ID FROM DEMO_PID.T_Drawing WHERE Name = 'DEMO-DWG-001');

/* Step 2 - delete the corrupted row (use the exact file name from step 1) */
DELETE FROM DEMO_PID.T_SmartFrame WHERE SP_FileName = '<CORRUPTED_FILE_NAME>';

/* Step 3 - delete storage records that no SmartFrame points to anymore */
DELETE FROM DEMO_PID.T_SmartFrameStorage
WHERE SP_ID NOT IN (SELECT SP_SmartFrameStorageID FROM DEMO_PID.T_SmartFrame);


/* B8. A constraint shows as violated during an import: disable it, finish the import,
       then enable it again. Always re-enable it. If re-enabling fails, find and fix
       the rows that violate it. */
ALTER TABLE DEMO_PID.T_LabelPersist DISABLE CONSTRAINT labelpersist_check;
COMMIT;
-- ... run the import ...
ALTER TABLE DEMO_PID.T_LabelPersist ENABLE CONSTRAINT labelpersist_check;
COMMIT;


/* =============================================================================
   C. UNDERSTANDING HOW SPPID STORES DATA
   ============================================================================= */

/* C1. How a line (pipe run) is stored: pipe run -> plant item -> model item ->
       representation -> connector -> connector vertex.

       What I learned:
       1. Every line has two kinds of representation: the main representation and a
          connector (when the line is a free line that is not connected).
       2. Every connector has vertices. A vertex is created at the start, at the end,
          and at every change of direction.
       3. If a vertex is connected to another item, it is no longer a free vertex;
          the connected item's ID is stored in SP_ConnectItem1ID / SP_ConnectItem2ID.
       4. If a valve is placed in the middle of a line, the line is split in two
          connectors. */
SELECT pr.SP_ID  AS PIPE_SP_ID,
       c.SP_ID   AS CONNECTOR_SP_ID,
       r.SP_ID   AS REP_ID,
       c.SP_ConnectItem1ID,
       c.SP_ConnectItem2ID,
       cv.SP_ID  AS CONNECTOR_VERTEX_SP_ID,
       cv.OrderIndex,
       cv.XCoordinate,
       cv.YCoordinate,
       pi.ItemTag,
       r.ItemStatus
FROM DEMO_PID.T_PipeRun pr
LEFT JOIN DEMO_PID.T_PlantItem pi       ON pr.SP_ID = pi.SP_ID
LEFT JOIN DEMO_PID.T_ModelItem mi       ON pi.SP_ID = mi.SP_ID
LEFT JOIN DEMO_PID.T_Representation r   ON mi.SP_ID = r.SP_ModelItemID
LEFT JOIN DEMO_PID.T_Connector c        ON r.SP_ID = c.SP_ID
LEFT JOIN DEMO_PID.T_ConnectorVertex cv ON c.SP_ID = cv.SP_ConnectorID
LEFT JOIN DEMO_PID.T_Drawing d          ON d.SP_ID = r.SP_DrawingID
WHERE pr.SP_ID = '<PIPE_RUN_ID>'
ORDER BY pr.SP_ID;


/* C2. Relation between instruments and their process signal line (3 steps, adding a table each time) */

-- Step 1: instrument + representation + drawing
SELECT I.SP_ID AS I_SP, I.SP_PipeRunID, R.SP_ID AS R_SP, D.Name, R.ItemStatus
FROM DEMO_PID.T_Instrument I
JOIN DEMO_PID.T_Representation R ON I.SP_PipeRunID = R.SP_ModelItemID
JOIN DEMO_PID.T_Drawing D        ON R.SP_DrawingID = D.SP_ID
ORDER BY I_SP;

-- Step 2: add the connector
SELECT I.SP_ID AS I_SP, I.SP_PipeRunID, R.SP_ID AS R_SP, C.SP_ID AS C_SP,
       C.SP_ConnectItem1ID, C.SP_ConnectItem2ID, D.Name, R.ItemStatus
FROM DEMO_PID.T_Instrument I
JOIN DEMO_PID.T_Representation R ON I.SP_PipeRunID = R.SP_ModelItemID
JOIN DEMO_PID.T_Connector C      ON R.SP_ID = C.SP_ID
JOIN DEMO_PID.T_Drawing D        ON R.SP_DrawingID = D.SP_ID
ORDER BY I_SP;

-- Step 3: add the connector vertices (coordinates of the signal line)
SELECT I.SP_ID AS I_SP, I.SP_PipeRunID, R.SP_ID AS R_SP, C.SP_ID AS C_SP,
       C.SP_ConnectItem1ID, C.SP_ConnectItem2ID, D.Name, R.ItemStatus,
       CV.OrderIndex, CV.XCoordinate, CV.YCoordinate
FROM DEMO_PID.T_Instrument I
JOIN DEMO_PID.T_Representation R ON I.SP_PipeRunID = R.SP_ModelItemID
JOIN DEMO_PID.T_Connector C      ON R.SP_ID = C.SP_ID
JOIN DEMO_PID.T_ConnectorVertex CV ON C.SP_ID = CV.SP_ConnectorID
JOIN DEMO_PID.T_Drawing D        ON R.SP_DrawingID = D.SP_ID
ORDER BY I_SP;


/* C3. Find piping components of a given type (e.g. gate valves) above a nominal diameter.
       NominalDiameter is stored in the database's internal units - check the value
       for your size (e.g. 3/4") in your own database first. */
SELECT pc.SP_ID, pi.SP_ID, pp.SP_ID, PipingCompType, PlantItemType, IsInline,
       NominalDiameter, PipingPointUsage, PipingPointNumber
FROM DEMO_PID.T_PipingComp pc
INNER JOIN DEMO_PID.T_PlantItem pi  ON pc.SP_ID = pi.SP_ID
INNER JOIN DEMO_PID.T_PipingPoint pp ON pp.SP_PlantItemID = pi.SP_ID
WHERE pp.NominalDiameter > <MIN_DIAMETER_IN_DB_UNITS>
  AND pc.PipingCompType IN (<GATE_VALVE_TYPE_CODE>)
ORDER BY pc.SP_ID;


/* C4. Find drawings that contain symbols outside the border.
       Step 1 - read the coordinates of symbols that sit in the four corners of the border,
       to learn the border limits (use valves/symbols placed at the corners of a test drawing). */
SELECT s.*
FROM DEMO_PID.T_Symbol s
INNER JOIN DEMO_PID.T_Representation r ON r.SP_ID = s.SP_ID
WHERE r.SP_ModelItemID IN ('<CORNER_ITEM_1>', '<CORNER_ITEM_2>', '<CORNER_ITEM_3>', '<CORNER_ITEM_4>');

/* Step 2 - list the drawings with symbols outside those limits (replace the numbers) */
SELECT DrawingNumber
FROM DEMO_PID.T_Drawing
WHERE SP_ID IN (
    SELECT d.SP_ID
    FROM DEMO_PID.T_Drawing d
    INNER JOIN DEMO_PID.T_Representation r ON d.SP_ID = r.SP_DrawingID
    INNER JOIN DEMO_PID.T_Symbol s         ON r.SP_ID = s.SP_ID
    WHERE s.XCoordinate <= <MIN_X>
       OR s.YCoordinate <= <MIN_Y>
       OR s.XCoordinate >= <MAX_X>
       OR s.YCoordinate >= <MAX_Y>
);


/* =============================================================================
   D. ORACLE ADMIN UTILITIES
   ============================================================================= */

/* D1. Name of the database you are connected to */
SELECT name FROM v$database;

/* D2. All users (schemas) in the database */
SELECT username FROM dba_users ORDER BY username;

/* D3. Default and temporary tablespace of one user */
SELECT username, default_tablespace, temporary_tablespace
FROM dba_users
WHERE username = 'DEMO_PID';

/* D4. All tablespaces */
SELECT tablespace_name, contents FROM dba_tablespaces;

/* D5. Find the tables that contain a specific column */
SELECT owner, table_name, column_name
FROM all_tab_columns
WHERE column_name = 'EMPLOYEE_ID';

/* D6. Who is using Drawing Manager on this database right now */
SELECT username, program, machine
FROM v$session
WHERE program LIKE '%drawingmanager%';
