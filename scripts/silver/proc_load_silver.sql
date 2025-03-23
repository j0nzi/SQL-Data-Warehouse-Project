/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process to 
    populate the 'silver' schema tables from the 'bronze' schema.
	Actions Performed:
		- Truncates Silver tables.
		- Inserts transformed and cleansed data from Bronze into Silver tables.
		
Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC Silver.load_silver;
===============================================================================
*/
EXEC bronze.load_bronze
EXEC silver.load_silver

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	-- Final Ingestion for silver.crm_cust_info)
	TRUNCATE TABLE silver.crm_cust_info;
	INSERT INTO silver.crm_cust_info (
		cst_id,
		cst_key,
		cst_firstname,
		cst_lastname,
		cst_marital_status,
		cst_gndr,
		cst_create_date)
	SELECT
	cst_id,
	cst_key,
	TRIM(cst_firstname) AS cst_firstname,
	TRIM(cst_lastname) AS cst_lastname,
	CASE	WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
			WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
			ELSE 'n/a'
	END cst_marital_status, -- Normalize marital status values to readable format
	CASE	WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
			WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
			ELSE 'n/a'
	END cst_gndr, -- Normalize gender values to readable format
	cst_create_date
	FROM (
		SELECT 
			*,
			ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
		FROM bronze.crm_cust_info
		WHERE cst_id IS NOT NULL
	) t 
	WHERE flag_last = 1 -- Select the most recent record per customer


	-- Final Ingestion for silver.crm_prd_info)
	TRUNCATE TABLE silver.crm_prd_info;
	INSERT INTO silver.crm_prd_info (
		prd_id,       
		cat_id,		 
		prd_key,      
		prd_name,     
		prd_cost,     
		prd_line,     
		prd_start_dt,
		prd_end_dt  
	)
	SELECT 
		prd_id,
		REPLACE(SUBSTRING(prd_key, 1,5), '-', '_') AS cat_id,
		SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,
		prd_name,
		ISNULL(prd_cost, 0) AS prd_cost,
		CASE	UPPER(TRIM(prd_line))
				WHEN	'M' THEN 'Mountain'
				WHEN	'R' THEN 'Road'
				WHEN	'S' THEN 'Other Sales'
				WHEN	'T' THEN 'Touring'
				ELSE 'n/a'
		END AS prd_line,
		CAST (prd_start_dt AS DATE) as prd_start_dt,
		CAST (DATEADD(day, -1, LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)) AS DATE) AS prd_end_dt
	FROM bronze.crm_prd_info

	-- Final Ingestion for silver.crm_sales_details)
	TRUNCATE TABLE silver.crm_sales_details;
	INSERT INTO silver.crm_sales_details(
		sls_ord_num,
		sls_prd_key,
		sls_cust_id,
		sls_order_dt,
		sls_ship_dt,
		sls_due_dt,
		sls_sales,
		sls_quantity,
		sls_price
	)
	SELECT
		sls_ord_num,
		sls_prd_key,
		sls_cust_id,
		sls_order_dt,
		sls_ship_dt,
		sls_due_dt,
		CASE 
			WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
			THEN sls_quantity * ABS(sls_price)
			ELSE sls_sales
		END AS sls_sales, -- Recalculate sales if orignal value is missing or incorrect
		sls_quantity,
		CASE 
			WHEN sls_price IS NULL OR sls_price <= 0
			THEN sls_sales / NULLIF(sls_quantity, 0)
			ELSE sls_price
		END AS sls_price -- Derive price if original value is invalid
	FROM bronze.crm_sales_details

	-- Final Ingestion for silver.erp_cust_az12)
	TRUNCATE TABLE silver.erp_cust_az12;
	INSERT INTO silver.erp_cust_az12 (cid, bdate,gen)
	-- Final Data Cleaning syntax
	SELECT
	CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
		ELSE cid
	END AS cid,
	CASE WHEN bdate  > GETDATE() THEN NULL
		ELSE bdate
	END as bdate,
	CASE	WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
			WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
			ELSE 'n/a'
	END AS gen
	FROM bronze.erp_cust_az12


	-- Final Ingestion for silver.erp_loc_a101 )
	TRUNCATE TABLE silver.erp_loc_a101;
	INSERT INTO silver.erp_loc_a101 
	(cid, cntry)
	SELECT
	REPLACE(cid, '-', '') cid,
	CASE	WHEN TRIM(cntry) = 'DE' THEN 'Germany'
			WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
			WHEN TRIM(cntry) = '' OR cntry IS NULL then 'n/a'
			ELSE TRIM(cntry)
	END cntry -- Normalize and Handle missing or blank country codes
	FROM bronze.erp_loc_a101

	-- Final Ingestion for silver.erp_px_cat_g1v2)
	TRUNCATE TABLE silver.erp_loc_a101;
	INSERT INTO silver.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance
	)
	SELECT 
	id,
	cat,
	subcat,
	maintenance
	FROM bronze.erp_px_cat_g1v2
END
