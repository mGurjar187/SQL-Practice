-- Query to find number of sales in each month.

SELECT 
	DATE_TRUNC('month', sales_transaction_date) month_date,
	count(1) number_of_sales
FROM sales
WHERE EXTRACT(YEAR FROM sales_transaction_date) = 2018
GROUP BY 1
ORDER BY 1;

-- Query to find number of new customers added each month

SELECT 
	DATE_TRUNC('month', date_added) month_date,
	count(1) number_of_new_customers
FROM customers
WHERE EXTRACT(YEAR FROM date_added) = 2018
GROUP BY 1
ORDER BY 1;

-- Installing packages to find distance between location points

CREATE EXTENSION cube;
CREATE EXTENSION earthdistance;

-- Exercise #23
-- 1. Create a Temp Table with location point for each customer.

CREATE TEMP TABLE customer_points AS(
	SELECT 
		customer_id,
		point(longitude, latitude) AS long_lat_point
FROM customers
WHERE longitude IS NOT NULL
AND latitude IS NOT NULL
);

-- 2. Create temp table for each dealership as well.

CREATE TEMP TABLE dealership_points AS(
	SELECT 
		dealership_id,
		point(longitude, latitude) AS long_lat_point
FROM dealerships
);

-- 3. Cross Join these two tables to find distance between each customer and each dealership.

CREATE TEMP TABLE customer_dealership_distance AS(
	SELECT 
		c.customer_id,
		d.dealership_id,
		c.long_lat_point <@> d.long_lat_point AS distance_in_miles
FROM customer_points c CROSS JOIN dealership_points d
);

-- 4. Find closest dealership for each customer.

CREATE TEMP TABLE closest_dealerships AS(
	SELECT
		DISTINCT ON (customer_id) 
		customer_id,
		dealership_id,
		distance_in_miles 
FROM customer_dealership_distance
ORDER BY customer_id, distance_in_miles
);

-- 5. Calculating average distance and median distance from each customer to their closest dealership.

SELECT 
	AVG(distance_in_miles), 
	PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY distance_in_miles)
FROM closest_dealerships;

-- Exercise #24 JSONB
-- 1. Getting each sales item using JSON_ARRAY_ELEMENTS function

CREATE TEMP TABLE customer_sales_single_sale_json AS(
	SELECT 
		customer_json,
		JSONB_ARRAY_ELEMENTS(customer_json -> 'sales') AS sales_json 
	FROM customer_sales 
);

-- 2. Filtering the output with product name Blade. 

SELECT 
	DISTINCT customer_json  
	FROM customer_sales_single_sale_json
	WHERE sales_json ->> 'product_name' =  'Blade';

-- 3. Using JSONB_PRETTY() to format the output.

SELECT 
	DISTINCT JSONB_PRETTY(customer_json)  
	FROM customer_sales_single_sale_json
	WHERE sales_json ->> 'product_name' =  'Blade';
	
-- Exercise #25 Text Analytics

-- 1. Customer survey table 

SELECT * FROM customer_survey;

-- 2. Parsing the feedback into individual words with their associated ratings

SELECT 
	UNNEST(STRING_TO_ARRAY(feedback,' ')) AS word,
	rating
FROM customer_survey;

-- 3. Standardize the text using ts_lexize() with stemmer 'english_stem' and REGEXP_REPLACE()

SELECT 
	(ts_lexize('english_stem'
				,UNNEST(STRING_TO_ARRAY(
					REGEXP_REPLACE(feedback,'[^a-zA-Z]+',' ', 'g'),
					' '))))[1] AS token,
	rating
FROM customer_survey;

-- 4. Calculate average rating for each token using GROUP_BY clause.

SELECT 
	(ts_lexize('english_stem'
				,UNNEST(STRING_TO_ARRAY(
					REGEXP_REPLACE(feedback,'[^a-zA-Z]+',' ', 'g'),
					' '))))[1] AS token,
	AVG(rating)
FROM customer_survey
GROUP BY 1
HAVING COUNT(1) >=3
ORDER BY 2;

-- 5. Verify survey resoponses that contains these tokens.

SELECT * FROM customer_survey WHERE feedback ILIKE '%pop%';

-- Activity 9 Sales Search and Analysis

-- 1. Creating a searchable materialized view on customer sales table.

CREATE MATERIALIZED VIEW customer_sales_search AS (
	SELECT 
		customer_json -> 'customer_id' AS customer_id,
		customer_json,
		to_tsvector('english', customer_json) AS searchable
	FROM customer_sales
);

-- 2. Creating Generalized Inverted Index(GIN) on view.

CREATE INDEX idx_customer_sales_search_searchable ON customer_sales_search USING GIN(searchable);

-- 3. Finding the customer with name of Danny who purchased Bat Scooter.

SELECT 
	customer_id,
	JSONB_PRETTY(customer_json)
FROM customer_sales_search 
WHERE searchable @@ plainto_tsquery('english','Danny Bat');

-- 4. Finding the number of times scooter and automobile is purchased together.

SELECT 
	sub.query,
	(SELECT 
		COUNT(1)
	FROM customer_sales_search
	WHERE customer_sales_search.searchable @@ sub.query) 
FROM (SELECT DISTINCT
		plainto_tsquery('english',p1.model) &&
		plainto_tsquery('english',p2.model) AS query
	FROM products p1
	CROSS JOIN products p2
	where p1.product_type = 'scooter'
	AND p2.product_type = 'automobile'
	AND p1.model NOT LIKE '%Limited Edition%'
	) 
ORDER BY 2 DESC;

-- Activity 13 Impementing Joins

-- 1. Find customers to whome emails has been sent.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	e.email_subject,
	e.opened,
	e.clicked
FROM customers c 
INNER JOIN emails e
ON c.customer_id = e.customer_id;

-- 2. Save the above query in customer_emails table.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	e.email_subject,
	e.opened,
	e.clicked
INTO customer_emails
FROM customers c 
INNER JOIN emails e
ON c.customer_id = e.customer_id;

-- 3. Find customers who opened or clicked the email sent.

SELECT * FROM customer_emails WHERE clicked = 't' AND opened = 't';

-- 4. Find the customers who dealership in their city.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	c.city
FROM customers c
LEFT JOIN dealerships d
ON c.city = d.city;

-- 5. Save the above query to table customer_dealers.

SELECT 
	c.customer_id,
	c.first_name,
	c.last_name,
	c.city
INTO customer_dealers
FROM customers c
LEFT JOIN dealerships d
ON c.city = d.city;

-- 6. List the customers who do not have dealershi in their city.

SELECT * FROM customer_dealers WHERE city IS NULL;

-- Activity 16 Averages Purchases Trigger

-- 1. Create avg qty log table.

CREATE TABLE avg_qty_log (
	order_id integer,
	avg_qty numeric
);

-- 2. Create function avg_qty that calculates average of quantity, updates avg_qty_log table and returns a trigger.

DROP FUNCTION IF EXISTS avg_qty();

CREATE FUNCTION avg_qty() RETURNS TRIGGER AS $avg_trigger$
DECLARE avg_qty numeric;
BEGIN
	SELECT AVG(qty) INTO avg_qty FROM order_info;
	INSERT INTO avg_qty_log (order_id, avg_qty) VALUES (NEW.order_id, avg_qty);
RETURN NEW;
END; $avg_trigger$
LANGUAGE PLPGSQL;

-- 3. Creating avg_trigger trigger after insert on order_info table.

DROP TRIGGER IF EXISTS avg_trigger ON order_info;

CREATE TRIGGER avg_trigger
AFTER INSERT ON order_info
FOR EACH ROW
EXECUTE PROCEDURE avg_qty();

-- 4. Inserting rows into order info table using insert_order()

SELECT insert_order(3, 'GROG1', 6);
SELECT insert_order(4, 'GROG1', 7);
SELECT insert_order(1, 'GROG1', 8);

-- 5. Verifying the result in avg_qty_log table 

SELECT * FROM avg_qty_log;

