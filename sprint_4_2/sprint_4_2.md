## Задание.

Ваша задача — найти пять самых медленных скриптов и оптимизировать их. Важно: при оптимизации в этой части проекта нельзя менять структуру БД.
В решении укажите способ, которым вы искали медленные запросы, а также для каждого из пяти запросов:
Составьте план запроса до оптимизации.
Укажите общее время выполнения скрипта до оптимизации (вы можете взять его из параметра actual time в плане запроса).
Отметьте узлы с высокой стоимостью и опишите, как их можно оптимизировать.
Напишите и вложите в решение все необходимые скрипты для оптимизации запроса.
Составьте план оптимизированного запроса.
Опишите, что изменилось в плане запроса после оптимизации.
Укажите общее время выполнения запроса после оптимизации.
План запроса вы составляете для себя. Опираясь на план, в решении опишите словами проблемные места и что стало лучше после изменений. Можно частично скопировать план, чтобы показать самые важные места. Не прикладывайте скриншоты плана запроса к решению — в таком формате ревьюер не сможет их прочитать.
В двух самых тяжёлых запросах можно сократить максимальную стоимость в несколько тысяч раз. В двух менее тяжёлых запросах можно увеличить производительность примерно в 100 и в 6 раз. В оставшемся запросе достаточно повысить производительность на 30%.

## Решение.
Запустим запросы из файла. Статистика сброиться.   
Пять самых медленных запросов выведем с использование модуля pg_stat_statements и запроса

```SQL
SELECT  
    query,
    ROUND(mean_exec_time::NUMERIC,2) AS mean,
    ROUND(total_exec_time::NUMERIC,2) AS total,
    ROUND(min_exec_time::NUMERIC,2) AS min, 
    ROUND(max_exec_time::NUMERIC,2) AS max,
    calls,
    rows,
    -- вычисление % времени, потраченного на запрос, относительно других запросов                          
    ROUND((100 * total_exec_time / sum(total_exec_time) OVER())::NUMERIC, 2) 
        AS percent
FROM pg_stat_statements
-- Подставьте своё значение dbid. SELECT oid, datname FROM pg_database;
WHERE dbid = 74735 ORDER BY mean_exec_time DESC
LIMIT 5; 

```

Видим, что запросы 9,8,7,2,15 - самые медленные. Начнем оптиизацию.

### Запрос №9. 
```SQL
EXPLAIN ANALYZE
-- 9
-- определяет количество неоплаченных заказов
SELECT count(*)
FROM order_statuses os
    JOIN orders o ON o.order_id = os.order_id
WHERE (SELECT count(*)
	   FROM order_statuses os1
	   WHERE os1.order_id = o.order_id AND os1.status_id = 2) = 0
	AND o.city_id = 1;

```
```
Aggregate  (cost=61066953.43..61066953.44 rows=1 width=8) (actual time=15886.520..15886.522 rows=1 loops=1)
```

Из плана запроса видно, что самые узкие места это 
### 1.
```
  ->  Nested Loop  (cost=0.30..61066953.20 rows=90 width=0) (actual time=85.250..15677.188 rows=1190 loops=1)
```
При соединении таблиц вложенными циклами.

### 2.
В подзапросе 

```
SubPlan 1
    ->  Aggregate  (cost=2681.01..2681.02 rows=1 width=8) (actual time=3.909..3.910 rows=1 loops=3958)
        ->  Seq Scan on order_statuses os1  (cost=0.00..2681.01 rows=1 width=0) (actual time=2.495..3.901 rows=1 loops=3958)
```
Агрегирование данных ```Aggregate``` и медленное ```Seq Scan``` последовательное чтение из таблицы ```order_statuses```
 
В общем удалось оптимизировать запрос добавив индекс на city_id (где-то 1-2 мс) 
и оптимизровав запрос след. образом

```SQL
CREATE INDEX city_id_idx ON orders(city_id);

WITH 
sub_orders AS (
	SELECT 
		o.order_id
	FROM orders o
    WHERE o.city_id = 1
), 
not_paid AS (
	SELECT order_id FROM order_statuses os WHERE os.status_id = 2
)
SELECT COUNT(*) FROM sub_orders so
LEFT JOIN (SELECT order_id FROM not_paid) ord ON ord.order_id = so.order_id
WHERE ord.order_id IS NULL 
--WHERE so.order_id NOT IN (SELECT order_id FROM not_paid)
```
```
Aggregate  (cost=2939.79..2939.80 rows=1 width=8) (actual time=8.348..8.351 rows=1 loops=1)
```

Стоимость запроса сократилась в 20 772 (61066953.44/2939.80) раза, время выполнения в
1902 (15886.52/8.35) раз быстрее.

### Запрос № 8.

```SQL
-- 8
-- ищет логи за текущий день
SELECT *
FROM user_logs
WHERE datetime::date > current_date;
```
```
    Append  (cost=0.00..155985.80 rows=1550780 width=83) (actual time=424.093..424.094 rows=0 loops=1)
```

Из плана запроса видно, что самые узкие места это 
```
->  Seq Scan on user_logs user_logs_1  (cost=0.00..39193.25 rows=410081 width=83) (actual time=117.629..117.629 rows=0 loops=1)
->  Seq Scan on user_logs_y2021q2 user_logs_2  (cost=0.00..108211.83 rows=1132263 width=83) (actual time=303.992..303.992 rows=0 loops=1)
->  Seq Scan on user_logs_y2021q3 user_logs_3  (cost=0.00..826.82 rows=8435 width=83) (actual time=2.461..2.462 rows=0 loops=1)
->  Seq Scan on user_logs_y2021q4 user_logs_4  (cost=0.00..0.00 rows=1 width=584) (actual time=0.004..0.004 rows=0 loops=1)
```
Идет последовательное сканирование всех партиций базовой таблицы ```user_logs```
не применяется индексирование на ```user_logs_datetime_idx``` из-за приведения типа ```datetime::date```

Исправим это

```SQL
SELECT *
FROM user_logs
WHERE datetime BETWEEN current_date::TIMESTAMP AND CONCAT(current_date, ' ', '23:59:59')::TIMESTAMP;
```
```
Append  (cost=0.44..25.27 rows=4 width=208) (actual time=0.021..0.022 rows=0 loops=1)
```
В плане запроса применилось индексное сканирование данных.
Стоимость запроса сократилась в 6172.77 (155985.80/25.27) раза, время выполнения в
19276.82 (424.09/0.022) раз быстрее.

### Запрос № 7.

```SQL
-- 7
-- ищет действия и время действия определенного посетителя
SELECT event, datetime
FROM user_logs
WHERE visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'
ORDER BY 2;
```
```
Gather Merge  (cost=92105.03..92128.37 rows=200 width=19) (actual time=106.254..108.354 rows=10 loops=1)
```

Из плана запроса видно, что ```Gather Merge``` объединяет несколько параллельных потоков, которые в свою очередь отрабатывают не по индексу, а полным перебором 
```
    ->  Parallel Seq Scan on user_logs_y2021q2 user_logs_2  (cost=0.00..66459.61 rows=60 width=18) (actual time=27.821..76.655 rows=2 loops=3)
    ->  Parallel Seq Scan on user_logs user_logs_1  (cost=0.00..24071.52 rows=32 width=18) (actual time=22.397..41.338 rows=2 loops=2)
    ->  Parallel Seq Scan on user_logs_y2021q3 user_logs_3  (cost=0.00..570.06 rows=10 width=18) (actual time=1.605..1.605 rows=0 loops=1)
    ->  Parallel Seq Scan on user_logs_y2021q4 user_logs_4  (cost=0.00..0.00 rows=1 width=282) (actual time=0.001..0.001 rows=0 loops=1)
```
Избавимся от такого поведения, добавив индекс по ```visitor_uuid```

```SQL
CREATE INDEX user_logs_visitor_uuid_idx ON user_logs(visitor_uuid); 
CREATE INDEX user_logs_y2021q2_visitor_uuid_idx ON user_logs_y2021q2(visitor_uuid); 
CREATE INDEX user_logs_y2021q3_visitor_uuid_idx ON user_logs_y2021q3(visitor_uuid); 
CREATE INDEX user_logs_y2021q4_visitor_uuid_idx ON user_logs_y2021q4(visitor_uuid); 
```
В результате
```SQL
EXPLAIN ANALYZE
SELECT event, datetime
FROM user_logs
WHERE visitor_uuid = 'fd3a4daa-494a-423a-a9d1-03fd4a7f94e0'
ORDER BY 2;
```
```
Sort  (cost=934.97..935.57 rows=240 width=19) (actual time=0.085..0.086 rows=10 loops=1)
```

Благодаря ```Bitmap Index Scan``` cтоимость запроса сократилась в 98 (92128.37/935.57) раз, время выполнения в 1260 (108.354/0.086) раз быстрее.


### Запрос №2.

```SQL
-- 2
-- выводит данные о конкретном заказе: id, дату, стоимость и текущий статус
SELECT o.order_id, o.order_dt, o.final_cost, s.status_name
FROM order_statuses os
    JOIN orders o ON o.order_id = os.order_id
    JOIN statuses s ON s.status_id = os.status_id
WHERE o.user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid
	AND os.status_dt IN (
	SELECT max(status_dt)
	FROM order_statuses
	WHERE order_id = o.order_id
    );
```
```
Nested Loop  (cost=15.51..33355.49 rows=7 width=46) (actual time=40.763..85.870 rows=2 loops=1)
```
```SQL
WITH 
sub_orders AS (SELECT 
	os.order_id, 
	o.final_cost,
	max(status_dt) max_status_dt,
	s.status_name
FROM order_statuses os
JOIN orders o ON o.order_id = os.order_id AND o.user_id = 'c2885b45-dddd-4df3-b9b3-2cc012df727c'::uuid
JOIN statuses s ON s.status_id = os.status_id
GROUP BY 
	os.order_id, 	
	o.final_cost,
	s.status_name),
final_orders AS(
SELECT 
	order_id,
	max_status_dt,
	final_cost,
	status_name,
	ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY max_status_dt DESC) rank
FROM sub_orders)
SELECT 
	order_id,
	max_status_dt,
	final_cost,
	status_name
FROM final_orders 
WHERE rank = 1;
```
```
Subquery Scan on final_orders  (cost=2543.76..2545.12 rows=1 width=46) (actual time=10.773..10.780 rows=2 loops=1)
```
Время запроса сократилось в 7,97 (85.870 / 10.780) раз. Здесь больше ориентировался на рекомендации в теории "Большие последовательности в условии WHERE ... IN по возможности заменяйте на JOIN".

### Запрос № 15.

```SQL
    -- 15
-- вычисляет количество заказов позиций, продажи которых выше среднего
SELECT d.name, SUM(count) AS orders_quantity
FROM order_items oi
    JOIN dishes d ON d.object_id = oi.item
WHERE oi.item IN (
	SELECT item
	FROM (SELECT item, SUM(count) AS total_sales
		  FROM order_items oi
		  GROUP BY 1) dishes_sales
	WHERE dishes_sales.total_sales > (
		SELECT SUM(t.total_sales)/ COUNT(*)
		FROM (SELECT item, SUM(count) AS total_sales
			FROM order_items oi
			GROUP BY
				1) t)
)
GROUP BY 1
ORDER BY orders_quantity DESC;
```
```
Sort  (cost=4808.91..4810.74 rows=735 width=66) (actual time=55.279..55.294 rows=362 loops=1)
```
Посмотрев на код можно заметить дублирование запроса. Вынесем в CTE.
```SQL
SELECT item, SUM(count) AS total_sales
FROM order_items oi
GROUP BY 1
```
При расчете среднего можно воспользоваться AVG функцией и перенести WHERE ... IN в JOIN

Получившийся запрос

```SQL
WITH 
dishes_sales AS (
	SELECT item, SUM(count) AS total_sales
	FROM order_items oi
	GROUP BY 1
),
top_items AS (
	SELECT item
	FROM dishes_sales
	WHERE dishes_sales.total_sales > (
		SELECT AVG(t.total_sales)
		FROM dishes_sales t)
)
SELECT d.name, SUM(count) AS orders_quantity
FROM order_items oi
JOIN dishes d ON d.object_id = oi.item
JOIN top_items ON top_items.item = oi.item
GROUP BY 1
ORDER BY orders_quantity DESC;
```
```
Sort  (cost=3344.89..3346.72 rows=735 width=66) (actual time=27.513..27.527 rows=362 loops=1)
```

Стоимость запроса снизилась на 43% (4810.74*100/3346.72 - 100), время сократилось в два раза (55.294 / 27.527 ). 