/*
	Этап 1
*/

/*
	Шаг 2 - 5
*/
DROP SCHEMA IF EXISTS raw_data CASCADE;
CREATE SCHEMA raw_data;
CREATE TABLE raw_data.sales (
	id INTEGER,
	auto TEXT,
	gasoline_consumption NUMERIC(3,1), 
	price NUMERIC(9,2),
	date DATE,
	person VARCHAR(30),
	phone VARCHAR(30),
	discount SMALLINT,
	brand_origin VARCHAR(30)
);
-- docker exec -it postgres_15 psql -U root -d sprint_1
-- \COPY raw_data.sales FROM '/db/cars.csv' WITH DELIMITER AS ',' NULL 'null' CSV HEADER;

COPY raw_data.sales FROM '/db/cars.csv' WITH DELIMITER AS ',' NULL 'null' CSV HEADER;

/*
	Шаг 6 -8
*/
DROP SCHEMA IF EXISTS car_shop CASCADE;
CREATE SCHEMA car_shop;

CREATE TABLE car_shop.persons (
	person_id SERIAL PRIMARY KEY,
	name VARCHAR(40) NOT NULL,
	phone VARCHAR(30) NOT NULL
);

INSERT INTO car_shop.persons (
	name,
	phone
) 
SELECT 
	person name,
	phone
FROM raw_data.sales
GROUP BY person, phone;

CREATE TABLE car_shop.countries (
	country_id SERIAL PRIMARY KEY,
	name VARCHAR(20)
);

INSERT INTO car_shop.countries (
	name
) 
SELECT DISTINCT raw_data.sales.brand_origin name 
FROM raw_data.sales
WHERE raw_data.sales.brand_origin IS NOT NULL;

CREATE TABLE car_shop.brands (
	brand_id SERIAL PRIMARY KEY,
	country_id INTEGER REFERENCES car_shop.countries (country_id),
	name VARCHAR(20) NOT NULL UNIQUE
);

INSERT INTO car_shop.brands (
	name,
    country_id
) 
SELECT 
	DISTINCT SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 1) name,
	c.country_id country_id
FROM raw_data.sales
LEFT JOIN car_shop.countries c ON c.name = raw_data.sales.brand_origin;

CREATE TABLE car_shop.colors (
	color_id SERIAL PRIMARY KEY,
	name VARCHAR(20) NOT NULL
);

INSERT INTO car_shop.colors (name) 
SELECT 
	DISTINCT SPLIT_PART(raw_data.sales.auto, ',', 2) name 
FROM raw_data.sales;

CREATE TABLE car_shop.models (
	model_id SERIAL PRIMARY KEY,
	brand_id INTEGER REFERENCES car_shop.brands (brand_id),
	name VARCHAR(20) NOT NULL,
	gasoline_consumption NUMERIC(3,1)
);

INSERT INTO car_shop.models (
	name,
	gasoline_consumption,
	brand_id)
SELECT 
	DISTINCT 
		TRIM(
		CONCAT(
			SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 2),
			' ',
			SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 3)
		)) name,
	raw_data.sales.gasoline_consumption gasoline_consumption,
	b.brand_id brand_id
FROM raw_data.sales
JOIN car_shop.brands b 
	ON b.name = SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 1);



CREATE TABLE car_shop.sales (
	sale_id SERIAL PRIMARY KEY,
	model_id INTEGER REFERENCES car_shop.models (model_id),
	person_id INTEGER REFERENCES car_shop.persons (person_id),
	color_id INTEGER REFERENCES car_shop.colors (color_id),
	date Date NOT NULL,
	price NUMERIC(9,2),
	discount SMALLINT NOT NULL DEFAULT 0 CHECK (discount >= 0 AND discount < 51)
);

INSERT INTO car_shop.sales (
	model_id,
	person_id,
	color_id,
	date,
	price,
	discount
)
SELECT 
	m.model_id model_id,
	p.person_id person_id,
	c.color_id color_id,
	raw_data.sales.date date,
	raw_data.sales.price price,
	raw_data.sales.discount
FROM raw_data.sales
JOIN car_shop.models m 
	ON m.name = TRIM(
		CONCAT(
			SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 2),
			' ',
			SPLIT_PART(SPLIT_PART(raw_data.sales.auto, ',', 1), ' ', 3)
		))
JOIN car_shop.persons p
	ON p.name = raw_data.sales.person AND p.phone = raw_data.sales.phone
JOIN car_shop.colors c 
	ON c.name = SPLIT_PART(raw_data.sales.auto, ',', 2);

/* 
	Этап 2	
*/

/*
	Задание 1
	Напишите запрос, который выведет процент моделей машин, у которых нет параметра gasoline_consumption.
*/

SELECT 
	(COUNT(DISTINCT m.model_id) * 100) / 
	(SELECT COUNT(m.model_id) FROM car_shop.models m)
	AS nulls_percentage_gasoline_consumption
FROM car_shop.models m
WHERE m.gasoline_consumption IS NULL;

/*
	Задание 2
	Напишите запрос, который покажет название бренда и среднюю цену его автомобилей 
	в разбивке по всем годам с учётом скидки. Итоговый результат отсортируйте по названию бренда 
	и году в восходящем порядке. Среднюю цену округлите до второго знака после запятой.
*/

SELECT 
	b.name brand_name,
	EXTRACT(YEAR FROM s.date::timestamp) AS year,
	ROUND(AVG(s.price),2) price_avg
FROM car_shop.models m
JOIN car_shop.brands b USING(brand_id)
JOIN car_shop.sales s USING(model_id)
GROUP BY brand_name, year
ORDER BY brand_name, year; 

/*
	Задание 3
	Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки. 
	Результат отсортируйте по месяцам в восходящем порядке. 
	Среднюю цену округлите до второго знака после запятой.
*/
SELECT 
	EXTRACT(MONTH FROM s.date::timestamp) AS month,
	EXTRACT(YEAR FROM s.date::timestamp) AS year,
	ROUND(AVG(s.price),2) price_avg
FROM car_shop.models m
JOIN car_shop.sales s USING(model_id)
JOIN car_shop.brands b USING(brand_id)
GROUP BY month, year
HAVING EXTRACT(YEAR FROM s.date::timestamp) = 2022
ORDER BY month; 

/*
	Задание 4
	Используя функцию STRING_AGG, напишите запрос, который выведет список купленных машин у каждого
	пользователя через запятую. Пользователь может купить две одинаковые машины — это нормально. Название
	машины покажите полное, с названием бренда — например: Tesla Model 3. Отсортируйте по имени
	пользователя в восходящем порядке. Сортировка внутри самой строки с машинами не нужна.
*/

SELECT 
	p.name person,
	STRING_AGG(CONCAT(b.name, ' ', m.name ), ', ') cars
FROM car_shop.persons p
JOIN car_shop.sales s USING(person_id)
JOIN car_shop.models m USING (model_id)
JOIN car_shop.brands b USING (brand_id)
GROUP BY p.name;

/*
	Задание 5
	Напишите запрос, который вернёт самую большую и самую маленькую цену продажи автомобиля 
	с разбивкой по стране без учёта скидки. Цена в колонке price дана с учётом скидки.
*/


SELECT 
	c.name brand_origin,
	MAX(s.price*100/(100-s.discount))::Numeric(9,2) price_max,
	MIN(s.price*100/(100-s.discount))::Numeric(9,2) price_min
FROM car_shop.countries c
JOIN car_shop.brands b USING (country_id)
JOIN car_shop.models m USING (brand_id)
JOIN car_shop.sales s USING(model_id)
GROUP BY brand_origin;

/*
	Задание 6
	Напишите запрос, который покажет количество всех пользователей из США. Это пользователи, 
	у которых номер телефона начинается на +1.
*/

SELECT 
	COUNT(*) persons_from_usa_count
FROM car_shop.persons p
WHERE p.phone LIKE '+1%';
