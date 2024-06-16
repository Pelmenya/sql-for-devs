## Задание 1.

Клиенты сервиса начали замечать, что после нажатия на кнопку Оформить заказ система на какое-то время подвисает.
Вот команда для вставки данных в таблицу orders, которая хранит общую информацию о заказах:

```SQL
INSERT INTO orders
    (order_id, order_dt, user_id, device_type, city_id, total_cost, discount,
    final_cost)
SELECT MAX(order_id) + 1, current_timestamp,
    '329551a1-215d-43e6-baee-322f2467272d',
    'Mobile', 1, 1000.00, null, 1000.00
FROM orders;
```
```
Insert on orders  (cost=0.32..0.35 rows=0 width=0) (actual time=0.074..0.075 rows=0 loops=1)
```


Чтобы лучше понять, как ещё используется в запросах таблица orders, выполните запросы из этого файла:
orders_stat.sql

Не переживайте, если какой-то запрос ничего не вернул, — это нормально. Пустой результат — тоже результат.

Проанализируйте возможные причины медленной вставки новой строки в таблицу orders

### Ход рассуждений, действия.
Чтобы проанализировать, что можно улучшить, просмотрим запросы из файла и сам запрос. Видно, что все операции происходят с таблицей ```orders```. В таблице нет первичного ключа как ограничения ```constraint``` на order_id, что скорее всего нужно в будующем, но есть index orders_order_id_idx, что излишне, если будет PK на order_id (он автоматически создаст index по order_id для быстроты поиска). Просмотрев запрос вставки, можно заметить излишние операции по инкриминированию order_id его можно сделать автоинкрементом, да и сам запрос не нужен при автоинкременте. Поле discount по умолчанию можно сделать 0 (не NULL) и запрограммировать тригер на посчет final_cost. Для таблицы ```orders``` проверим после выполнения запросов из файла и вставок данных, все ли индексы нужны, т.к. лишние индексы тормозят добавление строк. Выполним команду:

```SQL
    SELECT * FROM  pg_stat_user_indexes WHERE relname = 'orders';
```

Из запроса видно, используются индексы ```orders_order_dt_idx```,```orders_user_id_idx``` и ```orders_pk```. Следовательно остальные не нужны. Удалим их. 

Общий скрипт 

```SQL

ALTER TABLE orders ADD CONSTRAINT orders_pk PRIMARY KEY (order_id);
CREATE SEQUENCE order_id_seq START 1 INCREMENT BY 1;
SELECT setval('order_id_seq', (SELECT MAX(order_id) FROM orders));
ALTER TABLE orders ALTER COLUMN order_id SET DEFAULT nextval('order_id_seq');  
ALTER TABLE orders ALTER COLUMN discount SET DEFAULT 0;

DROP INDEX 
	public.orders_order_id_idx, 
	public.orders_city_id_idx,
	public.orders_device_type_city_id_idx,
	public.orders_device_type_idx,
	public.orders_discount_idx,
	public.orders_final_cost_idx,
	public.orders_total_cost_idx,
	public.orders_total_final_cost_discount_idx;
```

Финальный запрос для вставки 
```SQL
    INSERT INTO orders
        (order_dt, user_id, device_type, city_id, total_cost, final_cost)
    VALUES 
    (
        current_timestamp,
        '329551a1-215d-43e6-baee-322f2467272d',
        'Mobile', 
        1, 
        1000.00, 
        1000.00
    );
```
```
Insert on orders  (cost=0.00..0.01 rows=0 width=0) (actual time=0.026..0.026 rows=0 loops=1)
```

## Задание 2.
Клиенты сервиса в свой день рождения получают скидку. Расчёт скидки и отправка клиентам промокодов происходит на стороне сервера приложения. Список клиентов возвращается из БД в приложение таким запросом:

```SQL
    SELECT user_id::text::uuid, first_name::text, last_name::text, 
        city_id::bigint, gender::text
    FROM users
    WHERE city_id::integer = 4
        AND date_part('day', to_date(birth_date::text, 'yyyy-mm-dd')) 
            = date_part('day', to_date('31-12-2023', 'dd-mm-yyyy'))
        AND date_part('month', to_date(birth_date::text, 'yyyy-mm-dd')) 
            = date_part('month', to_date('31-12-2023', 'dd-mm-yyyy'))
```
```
    Seq Scan on users  (cost=0.00..2843.22 rows=1 width=120) (actual time=2.024..6.217 rows=5 loops=1)
```

Каждый раз список именинников формируется и возвращается недостаточно быстро. Оптимизируйте этот процесс.

### Ход рассуждений, действия.
Для начала проанализируем таблицу users в запросе. Видим, что есть первичный ключ, значит поиск по нему достаточно быстрый. Но ключ представляет собой текстовое значение, хотя хранит тип данных ```uuid``` и нет значения по умолчанию. Перейдем к самому запросу. В глаза кидаются многочисленные преобразования данных, что замедляет поиск, а так же нет возможности использовать индекс (например поле city_id преобразуется зачем то из BIGINTEGER  в INTEGER и на нем нет индекса, да и городов на планете земля может уложится в INTEGER). По другим полям не оптимально использвание по нагрузке на память типа CHARACTER размерность 500, данные типа DATE так же хранятся в текстовом формате. Многочисленное преобразование дат к серверу и от серверу сильно тормозит получение данных.

Предложения сделать первичный ключ тип ```uuid``` и по умолчанию  DEFAULT GEN_RANDOM_UUID(), поменять тип city_id на INTEGER, first_name и last_name - VARCHAR(50),  gender - VARCHAR(10), birth_date и registration_date - DATE. Добавить индекс на city_id 

```SQL
    ALTER TABLE users ALTER COLUMN user_id TYPE UUID USING user_id::text::UUID;
    ALTER TABLE users ALTER COLUMN user_id SET DEFAULT GEN_RANDOM_UUID();
    ALTER TABLE users 
		ALTER COLUMN first_name TYPE VARCHAR(50),
		ALTER COLUMN last_name TYPE VARCHAR(50),
		ALTER COLUMN gender TYPE VARCHAR(10),
   		ALTER COLUMN city_id TYPE INTEGER,
		ALTER COLUMN birth_date TYPE DATE USING birth_date::DATE,
		ALTER COLUMN registration_date TYPE DATE USING registration_date::DATE;
    CREATE INDEX users_city_id_idx ON users (city_id);
```
Теперь оптимизируем запрос

```SQL
    SELECT user_id, first_name, last_name, 
        city_id, gender
    FROM users
    WHERE city_id = 4
        AND EXTRACT(DAY FROM birth_date) = 31
        AND EXTRACT(MONTH FROM birth_date) = 12
```
```
    Bitmap Heap Scan on users  (cost=18.26..176.19 rows=1 width=56) (actual time=0.217..0.429 rows=5 loops=1)
```

## Задание 3.

Также пользователи жалуются, что оплата при оформлении заказа проходит долго.
Разработчик сервера приложения Матвей проанализировал ситуацию и заключил, что оплата «висит» из-за того, что выполнение процедуры add_payment требует довольно много времени по меркам БД. 

Найдите в базе данных эту процедуру и подумайте, как можно ускорить её работу.

### Ход рассуждений, действия.

Найдем хранимую процедуру в базе, чтобы посмотреть ее код. При вставке в ```sales``` и ```order_statuses``` дважды вызывается statement_timestamp(), можно вынести в отдельную переменную. Посмотрим таблицы участвующие во вставке данных ```order_statuses, payments, sales```. Видно, данные из таблицы ```sales``` дублируются в ```payments```. Поэтому таблицу ```payments``` и последовательность ```payments_payment_id_sq``` можно удалить как и вставку в нее в хранимой процедуре.

Для оптимизации sales нужно сделать первичным ключом поле sale_id (это позволит добавить его в INDEX по умолчанию) и добавить дефолтное значение NEXTVAL('sales_sale_id_sq'), что позволит опустить указание sale_id при в ставке в процедуре. На всякий случай проверим, что последовательности существуют. На user_id и order_id(Задание 1) индексы есть.


```SQL
    DROP TABLE payments;
    DROP SEQUENCE payments_payment_id_sq;

    ALTER TABLE sales ADD CONSTRAINT sales_pk PRIMARY KEY (sale_id);
    ALTER TABLE sales ALTER COLUMN sale_id SET DEFAULT nextval('sales_sale_id_sq');  
    SELECT setval('sales_sale_id_sq', (SELECT MAX(sale_id) FROM sales));
```
Код хранимой процедуры

```SQL
    DECLARE 
	_cur_timestamp TIMESTAMP := statement_timestamp();
    _user_id UUID := (SELECT user_id FROM orders WHERE order_id = p_order_id);

    BEGIN
        INSERT INTO order_statuses (status_id, status_dt)
        VALUES (2, _cur_timestamp);
        
        INSERT INTO sales(sale_dt, user_id, sale_sum)
        VALUES (_cur_timestamp, _user_id, p_sum_payment);
    END;
```

## Задание 4.

Все действия пользователей в системе логируются и записываются в таблицу user_logs. Потом эти данные используются для анализа — как правило, анализируются данные за текущий квартал.
Время записи данных в эту таблицу сильно увеличилось, а это тормозит практически все действия пользователя. Подумайте, как можно ускорить запись. Вы можете сдать решение этой задачи без скрипта или — попробовать написать скрипт. Дерзайте!

### Ход рассуждений, действия.

Просмотрим таблицу. Таблица имеет большой объем данных. Так как данные нужны поквартально и таблица уже существует оптимальнее ее разбить на партиции через наследование. Таким образом запрос  на выборку в текущем квартале будет происходить быстрее и логирование также будет добавлятся в нужную партицию.

## Задание 5.

Маркетологи сервиса регулярно анализируют предпочтения различных возрастных групп. Для этого они формируют отчёт:
|      day     |    age     |    spicy     |    fish    |    meat    |
| ------------ | :--------: | :----------: | :--------: | :--------: |
|              |   `0–20`   |              |            |            |
|              |   `20–30`  |              |            |            |
|              |   `30–40`  |              |            |            |
|              |  `40–100`  |              |            |            |

---
В столбцах spicy, fish и meat отображается, какой % блюд, заказанных каждой категорией пользователей, содержал эти признаки.

В возрастных интервалах верхний предел входит в интервал, а нижний — нет.

Также по правилам построения отчётов в них не включается текущий день.

Администратор БД Серёжа заметил, что регулярные похожие запросы от разных маркетологов нагружают базу, и в результате увеличивается время работы приложения.

Подумайте с точки зрения производительности, как можно оптимально собирать и хранить данные для такого отчёта. В ответе на это задание не пишите причину — просто опишите ваш способ получения отчёта и добавьте соответствующий скрипт.

### Ход рассуждений, действия.

Так как в отчет не включается текущий день, оптимальней сделать материализованное представление для этого запроса. Осуществлять его REFRESH по окончанию рабочего дня. 

```SQL
DROP MATERIALIZED VIEW IF EXISTS different_age_people_statistics_of_products;

CREATE MATERIALIZED VIEW different_age_people_statistics_of_products AS (
WITH sub_orders AS (
SELECT 
	o.order_id,
	o.order_dt::DATE AS "day", 
	SUM(spicy  * count) spicy_sum, 
	SUM(fish * count) fish_sum, 
	SUM(meat * count) meat_sum,
	o.user_id
FROM order_items oi
JOIN orders o USING (order_id)
JOIN dishes d ON d.object_id = item
JOIN users u ON u.user_id = o.user_id
GROUP BY 	
	o.order_id,
	o.order_dt), 
sub_all AS (SELECT 
		so."day",
		CASE
			WHEN 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) > 0 AND 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) <= 20 THEN '0-20'
			WHEN 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) > 20 AND 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) <= 30 THEN '20-30'
			WHEN 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) > 30 AND 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) <= 40 THEN '30-40'
			WHEN 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) > 40 AND 
				EXTRACT (YEAR FROM CURRENT_DATE) - EXTRACT (YEAR FROM birth_date) <= 100 THEN '40-100'
			END age,
		spicy_sum, 
		fish_sum, 
		meat_sum
FROM sub_orders so
JOIN users USING (user_id))
SELECT 
	sa."day", 
	age, 	
	ROUND(SUM(spicy_sum)*100/(SUM(spicy_sum) + SUM(fish_sum) + SUM(meat_sum)), 2) spicy, 
	ROUND(SUM(fish_sum)*100/(SUM(spicy_sum) + SUM(fish_sum) + SUM(meat_sum)), 2) fish, 
	ROUND(SUM(meat_sum)*100/(SUM(spicy_sum) + SUM(fish_sum) + SUM(meat_sum)), 2) meat
FROM sub_all sa
GROUP BY sa."day", age);

SELECT * FROM different_age_people_statistics_of_products;
```