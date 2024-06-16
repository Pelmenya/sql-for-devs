-- Этап 1
-- CREATE DATABASE sprint_2;
-- CREATE EXTENSION PostGIS;
-- docker exec -i  postgres_postgis pg_restore -U postgres -v -d sprint_2 < ./dump/sprint2_dump.sql

DROP TYPE IF EXISTS cafe.restaurant_type CASCADE;
CREATE TYPE cafe.restaurant_type AS ENUM 
    ('coffee_shop', 'restaurant', 'bar', 'pizzeria');

DROP TABLE IF EXISTS cafe.restaurants CASCADE;
CREATE TABLE cafe.restaurants (
	restaurant_uuid uuid PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
	name VARCHAR(50) NOT NULL UNIQUE,
	location GEOMETRY(POINT, 4326) NOT NULL,
	type cafe.restaurant_type,
	menu JSONB NOT NULL
);
INSERT INTO cafe.restaurants(
	name, location, type, menu
)
SELECT 
	rds.cafe_name name,
	CONCAT('POINT(', rds.longitude, ' ', rds.latitude,')') location,
	rds.type::cafe.restaurant_type,
	rdm.menu menu
FROM raw_data.sales rds
JOIN raw_data.menu rdm ON rds.cafe_name = rdm.cafe_name 
GROUP BY 
	rds.cafe_name, 
	rds.type,  
	rds.latitude, 
	rds.longitude, 
	rdm.menu;

DROP TABLE IF EXISTS cafe.managers CASCADE;
CREATE TABLE cafe.managers (
	manager_uuid uuid PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
	name VARCHAR(50) NOT NULL,
	phone VARCHAR(50)
);
INSERT INTO cafe.managers (
	name,
	phone
)
SELECT 
	rds.manager name,
	rds.manager_phone phone
FROM raw_data.sales rds
GROUP BY 
	rds.manager, 
	rds.manager_phone;

DROP TABLE IF EXISTS cafe.restaurant_manager_work_dates CASCADE;
CREATE TABLE cafe.restaurant_manager_work_dates (
	restaurant_uuid UUID REFERENCES cafe.restaurants (restaurant_uuid),
	manager_uuid UUID REFERENCES cafe.managers (manager_uuid),
	work_start DATE NOT NULL,	
	work_end DATE NOT NULL,
	PRIMARY KEY (restaurant_uuid, manager_uuid)
);
INSERT INTO cafe.restaurant_manager_work_dates (
	restaurant_uuid,
	manager_uuid,
	work_start,	
	work_end
)
WITH rmd AS (SELECT
	restaurant_uuid,
	manager_uuid,
	report_date date
FROM raw_data.sales rds
JOIN cafe.managers cm ON cm.name = rds.manager
JOIN cafe.restaurants cr ON cr.name = rds.cafe_name
GROUP BY restaurant_uuid, manager_uuid, report_date)
SELECT  
	restaurant_uuid,
	manager_uuid,
	MIN(date) work_start,
	MAX(date) work_end
FROM rmd
GROUP BY restaurant_uuid, manager_uuid;

DROP TABLE IF EXISTS cafe.sales CASCADE;
CREATE TABLE cafe.sales (
	date DATE NOT NULL,
	avg_check NUMERIC(6,2),
	restaurant_uuid UUID REFERENCES cafe.restaurants (restaurant_uuid),
	PRIMARY KEY (restaurant_uuid, date)
);
INSERT INTO cafe.sales (
	date,
	avg_check,
	restaurant_uuid
)
WITH rmd AS (SELECT
	report_date date,
	avg_check,
	restaurant_uuid
FROM raw_data.sales rds
JOIN cafe.restaurants cr ON cr.name = rds.cafe_name)
SELECT * FROM rmd;

-- Этап 2.
/*
	Задание 1.
	Чтобы выдать премию менеджерам, нужно понять, у каких заведений самый высокий средний чек. 
	Создайте представление, которое покажет топ-3 заведений внутри каждого типа заведения 
	по среднему чеку за все даты. Столбец со средним чеком округлите до второго знака после запятой.
*/
	
CREATE VIEW top_restaurants_avg_check AS (
	WITH sub AS (
		SELECT 
			*,
			ROW_NUMBER() OVER(PARTITION BY type ORDER BY avg_check DESC) rank
		FROM (
			SELECT 
				name, 
				type, 
				ROUND(AVG(avg_check), 2) 
				avg_check 
			FROM cafe.sales
			JOIN cafe.restaurants USING(restaurant_uuid)
			GROUP BY name, type, restaurant_uuid)
	)
	SELECT  
		name AS "Название заведения",
		CASE
			WHEN type = 'coffee_shop' THEN 'Кофейня'
			WHEN type = 'restaurant' THEN 'Ресторан'
			WHEN type = 'bar' THEN 'Бар'
			WHEN type = 'pizzeria' THEN 'Пиццерия'
		END AS "Тип заведения",
		avg_check AS "Средний чек"
	FROM sub WHERE rank IN (1,2,3)
);
SELECT * FROM top_restaurants_avg_check;

/*
	Задание 2.
	Создайте материализованное представление, которое покажет, как изменяется средний чек 
	для каждого заведения от года к году за все года за исключением 2023 года. 
	Все столбцы со средним чеком округлите до второго знака после запятой.
*/

DROP MATERIALIZED VIEW IF EXISTS avg_check_year_to_year;
CREATE MATERIALIZED VIEW avg_check_year_to_year AS (
	WITH sub AS (
		SELECT 
			name, 
			type, 
			EXTRACT(YEAR FROM date::timestamp) AS year, ROUND(AVG(avg_check), 2) avg_check FROM cafe.sales
		JOIN cafe.restaurants USING(restaurant_uuid)
		GROUP BY name, type, year
	)
	SELECT 
	year AS "Год",
	name AS "Название заведения",
	CASE
		WHEN type = 'coffee_shop' THEN 'Кофейня'
		WHEN type = 'restaurant' THEN 'Ресторан'
		WHEN type = 'bar' THEN 'Бар'
		WHEN type = 'pizzeria' THEN 'Пиццерия'
	END AS "Тип заведения",
	avg_check AS "Средний чек этом году",
	LAG(avg_check) OVER() AS "Средний чек в предыдущем году",
	ROUND((avg_check - LAG(avg_check) OVER(PARTITION BY name ORDER BY year))/avg_check*100, 2) AS "Изменение среднего чека в %"
	FROM sub
	WHERE year <> 2023
);

SELECT * FROM avg_check_year_to_year;

/*
	Задание 3.
	Найдите топ-3 заведения, где чаще всего менялся менеджер за весь период.
*/
SELECT 
	name AS "Название заведения",
	COUNT(DISTINCT manager_uuid) AS "Сколько раз менялся менеджер"
FROM cafe.restaurant_manager_work_dates
JOIN cafe.restaurants USING(restaurant_uuid)
GROUP BY "Название заведения"
ORDER BY "Сколько раз менялся менеджер" DESC
LIMIT 3;

/*
	Задание 4.
	Найдите пиццерию с самым большим количеством пицц в меню. 
	Если таких пиццерий несколько, выведите все.
*/
WITH sub AS(
SELECT 
	name,
	COUNT(pizza) cn,
	DENSE_RANK() OVER(ORDER BY COUNT(pizza) DESC) rank
	FROM 
	(
		SELECT 
			cr.name,
			JSONB_EACH(cr.menu -> 'Пицца') pizza
		FROM cafe.restaurants cr
		WHERE cr.menu ? 'Пицца'
		GROUP BY cr.name, cr.menu
	)
GROUP BY name)
SELECT 
	name AS "Название заведения",
	cn AS "Количество пицц в меню"
FROM sub
WHERE rank = 1;

/*
	Задание 5.
	Найдите самую дорогую пиццу для каждой пиццерии.
*/

WITH sub AS (
	SELECT 
		name,
		key,
		value
	FROM cafe.restaurants, JSONB_EACH(menu -> 'Пицца')
	WHERE menu ? 'Пицца'
	GROUP BY name, menu, key, value)
SELECT 	
	name AS "Название заведения", 
	'Пицца' AS "Тип блюда",
	key AS "Название пиццы", 
	value AS "Цена"
 FROM (
SELECT  
	name, 
	key, 
	value::NUMERIC, 
	MAX(value::NUMERIC) OVER(PARTITION BY name) AS max_price
FROM sub
GROUP BY name, key, value)
WHERE max_price = value;

/*
	Задание 6.
	Найдите два самых близких друг к другу заведения одного типа.
*/
WITH sub AS (
	SELECT 
		cr.name AS name1,   
		crt.name AS name2,
		cr.type type,
		ST_Distance(cr.location::geography, crt.location::geography) distance
	FROM cafe.restaurants cr
	CROSS JOIN cafe.restaurants crt
	WHERE cr.type = crt.type AND  cr.name <> crt.name)
SELECT 
	name1 AS "Название Заведения 1",
	name2 AS "Название Заведения 2",
	CASE
		WHEN type = 'coffee_shop' THEN 'Кофейня'
		WHEN type = 'restaurant' THEN 'Ресторан'
		WHEN type = 'bar' THEN 'Бар'
		WHEN type = 'pizzeria' THEN 'Пиццерия'
	END AS "Тип заведения",
	distance AS "Расстояние"
FROM 
	(
		SELECT
		*,
		ROW_NUMBER() OVER(PARTITION BY type ORDER BY distance) rank
		FROM sub
	)
WHERE rank = 1;

/*
	Задание 7.
	Найдите район с самым большим количеством заведений и район с самым 
	маленьким количеством заведений. Первой строчкой выведите район с самым 
	большим количеством заведений, второй — с самым маленьким. 
*/
WITH sub AS (
	SELECT 
		DISTINCT district_name, 
		COUNT(*) OVER(PARTITION BY district_name) AS cafe_count
	FROM cafe.districts cd
	JOIN cafe.restaurants cr ON ST_Contains(cd.district_geom, cr.location)
	ORDER BY cafe_count
	)
SELECT 
	district_name AS "Название района",
	cafe_count AS "Количество заведений"
FROM (
	SELECT 
		district_name,
		cafe_count
	FROM sub
	LIMIT 1)
	UNION (
	SELECT 
		district_name,
		cafe_count
	FROM sub
	ORDER BY cafe_count DESC
	LIMIT 1)
ORDER BY "Количество заведений" DESC;
