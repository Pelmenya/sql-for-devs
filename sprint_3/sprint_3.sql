--CREATE DATABASE sprint_3;
/*
	Задание 1.
	В Dream Big ежемесячно оценивают производительность сотрудников. В результате бывает, кому-то повышают, 
	а изредка понижают почасовую ставку. Напишите хранимую процедуру update_employees_rate, которая обновляет
	почасовую ставку сотрудников на определённый процент. При понижении ставка не может быть 
	ниже минимальной — 500 рублей в час. Если по расчётам выходит меньше, устанавливают минимальную ставку.
*/
CREATE OR REPLACE PROCEDURE update_employees_rate (
	p_employees_rate JSON
)
LANGUAGE plpgsql
AS $$
DECLARE
    _el JSON;
	_arr JSON[] := ARRAY(SELECT json_array_elements(p_employees_rate));
	_new_rate INTEGER;
BEGIN
 FOREACH _el in ARRAY _arr
    LOOP
	   SELECT 
			(1 + (_el->>'rate_change')::NUMERIC/100)*rate
	   INTO _new_rate
	   FROM employees
	   WHERE id = (_el->>'employee_id')::UUID;
	   IF _new_rate > 500 THEN
		   UPDATE employees
       	   SET
		   	  rate = _new_rate
           WHERE
           id = (_el->>'employee_id')::UUID;
	   ELSE
		   UPDATE employees
       	   SET 
              rate = 500
           WHERE
           id = (_el->>'employee_id')::UUID;
	   END IF;
    END LOOP;
END;
$$;
	
/*CALL update_employees_rate(
    '[
        {"employee_id": "80718590-e2bf-492b-8c83-6f8c11d007b1", "rate_change": 10}, 
        {"employee_id": "63e80b67-06e0-49cd-ba26-ad520168d9b6", "rate_change": -5}
    ]'::JSON
);
*/
/*
	Задание 2.
	С ростом доходов компании и учётом ежегодной инфляции Dream Big индексирует зарплату всем сотрудникам.
	Напишите хранимую процедуру indexing_salary, которая повышает зарплаты всех сотрудников на определённый процент. 
	Процедура принимает один целочисленный параметр — процент индексации p. Сотрудникам, которые получают 
	зарплату по ставке ниже средней относительно всех сотрудников до индексации, начисляют дополнительные 2% (p + 2). 
	Ставка остальных сотрудников увеличивается на p%. Зарплата хранится в БД в типе данных integer, 
	поэтому если в результате повышения зарплаты образуется дробное число, его нужно округлить до целого.
*/

CREATE OR REPLACE PROCEDURE indexing_salary(
	p_p INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    _avg_rate NUMERIC;
BEGIN
	SELECT
		AVG(rate) 
	INTO _avg_rate
	FROM employees;
	UPDATE employees
	SET rate = ROUND(rate * (1 + (p_p + 2)::NUMERIC/100))
	WHERE rate < _avg_rate;  	
	UPDATE employees
	SET rate = ROUND(rate * (1 + p_p ::NUMERIC/100))
	WHERE rate >= _avg_rate;  	
END;
$$;

--CALL indexing_salary(10);

/*
Задание 3.
	Завершая проект, нужно сделать два действия в системе учёта:
	Изменить значение поля is_active в записи проекта на false — чтобы рабочее время по этому проекту больше не учитывалось.
	Посчитать бонус, если он есть — то есть распределить неизрасходованное время между всеми членами команды проекта. 
	Неизрасходованное время — это разница между временем, которое выделили на проект (estimated_time), и фактически потраченным. 
	Если поле estimated_time не задано, бонусные часы не распределятся. Если отработанных часов нет — расчитывать бонус не нужно.
	Разберёмся с бонусом. 
	Если в момент закрытия проекта estimated_time:
	не NULL, больше суммы всех отработанных над проектом часов,
	всем членам команды проекта начисляют бонусные часы.
	Размер бонуса считают так: 75% от сэкономленных часов делят на количество участников проекта, но не более 16 бонусных часов 
	на сотрудника. Дробные значения округляют в меньшую сторону (например, 3.7 часа округляют до 3). Рабочие часы заносят 
	в логи с текущей датой. Например, если на проект запланировали 100 часов, а сделали его за 30 — 3/4 от сэкономленных 70 часов 
	распределят бонусом между участниками проекта. Создайте пользовательскую процедуру завершения проекта close_project. 
	Если проект уже закрыт, процедура должна вернуть ошибку без начисления бонусных часов.
*/

CREATE OR REPLACE PROCEDURE close_project(
	p_project_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE 
	_is_active BOOLEAN;
	_sum_work_hours INTEGER;
	_estimated_time INTEGER;
	_count_employees INTEGER;
	_bonus_hours INTEGER;
	_employees UUID[];
	_el UUID;
BEGIN
	SELECT 
		is_active
	INTO 
		_is_active
	FROM projects WHERE id = p_project_id;
	IF _is_active THEN
		
		UPDATE projects
		SET is_active = false WHERE id = p_project_id;
		
		-- Потраченное время
		SELECT 
			SUM(work_hours)
		INTO _sum_work_hours
		FROM logs 
		WHERE project_id = p_project_id;

		-- Время на проект
		SELECT 
			estimated_time
		INTO _estimated_time
		FROM projects 
		WHERE id = p_project_id;

		IF _estimated_time IS NOT NULL AND _estimated_time > _sum_work_hours
			THEN
			-- UUID работников и их число в проекте
				_employees := 
						ARRAY(SELECT DISTINCT (e.id)
								FROM logs l
								JOIN employees  e ON l.employee_id = e.id
								WHERE l.project_id = p_project_id);

				SELECT ARRAY_LENGTH(_employees, 1) INTO _count_employees;
				-- Бонусные часы
				_bonus_hours = FLOOR(0.75 * (_estimated_time - _sum_work_hours)/_count_employees );

				FOREACH _el IN ARRAY _employees
					LOOP
						IF  _bonus_hours < 16
							THEN
								INSERT INTO logs(
									project_id, employee_id, work_date, work_hours
								)
								VALUES (
									p_project_id, _el, CURRENT_TIMESTAMP, _bonus_hours
								);
							ELSE
								INSERT INTO logs(
									project_id, employee_id, work_date, work_hours
								)
								VALUES (
									p_project_id, _el, CURRENT_TIMESTAMP, 16
								);
						END IF;
					END LOOP;
		END IF;
	ELSE
		RAISE EXCEPTION 'It is not possible to close the project again - %', _is_active;
	END IF;
END;
$$;

--CALL close_project('2dfffa75-7cd9-4426-922c-95046f3d06a0');

/*
	Задание 4.
	Напишите процедуру log_work для внесения отработанных сотрудниками часов. Процедура добавляет новые записи 
	о работе сотрудников над проектами. 
	
	Процедура принимает id сотрудника, id проекта, дату и отработанные часы 
	и вносит данные в таблицу logs. 
	
	Если проект завершён, добавить логи нельзя — процедура должна вернуть ошибку Project closed. 
	Количество залогированных часов может быть в этом диапазоне: от 1 до 24 включительно — нельзя внести менее 
	1 часа или больше 24. Если количество часов выходит за эти пределы, необходимо вывести предупреждение 
	о недопустимых данных и остановить выполнение процедуры.
	
	Запись помечается флагом required_review, если:
	 - залогированно более 16 часов за один день — Dream Big заботится о здоровье сотрудников;
	 - запись внесена будущим числом;
	 - запись внесена более ранним числом, чем на неделю назад от текущего дня — например, 
	   если сегодня 10.04.2023, все записи старше 3.04.2023 получат флажок.
*/

CREATE OR REPLACE PROCEDURE log_work(
	p_employee_id UUID,
	p_project_id UUID,
	p_work_date TEXT,
	p_work_hours INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE 
	_is_active BOOLEAN;
	_log_hours INTEGER;
	_flag_required_review BOOLEAN := false;
BEGIN
	SELECT 
		is_active
	INTO
		_is_active
	FROM projects
	WHERE id = p_project_id;

	IF _is_active THEN
		IF 	p_work_hours BETWEEN 1 AND 24 THEN
			-- Залогированные часы за день
			SELECT 
				SUM(work_hours)
			INTO _log_hours
			FROM logs
			WHERE 
				project_id = p_project_id
				AND work_date = p_work_date::DATE;
			IF _log_hours + p_work_hours > 16 THEN
				_flag_required_review := true;
			END IF;

			-- Запись будующим числом ?
			IF p_work_date::DATE > CURRENT_DATE THEN
				_flag_required_review := true;
			END IF;

			-- Запись внесена болеe ранним числом?
			IF p_work_date::DATE < CURRENT_DATE - '1 week'::interval THEN
				_flag_required_review := true;
			END IF;

			INSERT INTO logs (
				employee_id, project_id, work_date, work_hours, required_review
			)
			VALUES (
				p_employee_id, p_project_id, p_work_date::DATE, p_work_hours, _flag_required_review
			);

		ELSE
			RAISE EXCEPTION 'Work hours must be from 1 our to 24 hours';
		END IF;	
	ELSE
		RAISE EXCEPTION 'Project closed';
	END IF;
END;	
$$;
/*
CALL log_work(
    'bb10fcd0-c1fb-4b8a-ab1a-453db3603015', -- employee uuid
    '2dfffa75-7cd9-4426-922c-95046f3d06a0', -- project uuid
    '2024-05-27',                           -- work date
    4                                       -- worked hours
); 
*/

/*
	Задание 5.
	Чтобы бухгалтерия корректно начисляла зарплату, нужно хранить историю изменения почасовой ставки сотрудников. 
	Создайте отдельную таблицу employee_rate_history с такими столбцами:
	id — id записи,
	employee_id — id сотрудника,
	rate — почасовая ставка сотрудника,
	from_date — дата назначения новой ставки.

	Внесите в таблицу текущие данные всех сотрудников. В качестве from_date используйте дату основания компании: '2020-12-26'.
	
	Напишите триггерную функцию save_employee_rate_history и триггер change_employee_rate. 
	При добавлении сотрудника в таблицу employees и изменении ставки сотрудника триггер автоматически вносит запись 
	в таблицу employee_rate_history из трёх полей: id сотрудника, его ставки и текущей даты.
*/

DROP TABLE IF EXISTS employee_rate_history;
CREATE TABLE employee_rate_history(
	id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
	employee_id UUID,
	rate INTEGER,
	from_date DATE
);

INSERT INTO employee_rate_history 
SELECT GEN_RANDOM_UUID(), id, rate, '2020-12-26'::DATE
FROM employees;

CREATE OR REPLACE FUNCTION save_employee_rate_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- проверяем, что ставка изменилась, используя NULL SAFE сравнение
    IF OLD.rate IS DISTINCT FROM NEW.rate THEN
        -- сохраняем данные в таблицу
        INSERT INTO employee_rate_history (
            employee_id, rate, from_date
        )
        VALUES (
            NEW.id, NEW.rate, CURRENT_DATE
        );
    END IF;
    -- можем вернуть NULL, так как время события для триггера AFTER 
    -- и возврат функции ни на что не влияет
    RETURN NULL;
END
$$;

CREATE OR REPLACE TRIGGER save_employee_rate_history
AFTER UPDATE OR INSERT ON employees
FOR EACH ROW
EXECUTE FUNCTION save_employee_rate_history(); 
/* ТЕСТЫ ТРИГГЕРА
INSERT INTO employees (
	name,
	email,
	rate
) VALUES(
	'ddd', 'rr@ru.ru','1200'	
);
CALL update_employees_rate(
    '[
        {"employee_id": "80718590-e2bf-492b-8c83-6f8c11d007b1", "rate_change": 10}, 
        {"employee_id": "63e80b67-06e0-49cd-ba26-ad520168d9b6", "rate_change": -5}
    ]'::JSON
);
*/

/*
	Задание 6.
	После завершения каждого проекта Dream Big проводит корпоративную вечеринку, чтобы отпраздновать 
	очередной успех и поощрить сотрудников. Тех, кто посвятил проекту больше всего часов, награждают премией 
	«Айтиголик» — они получают почётные грамоты и ценные подарки от заказчика.

	Чтобы вычислить айтиголиков проекта, напишите функцию best_project_workers.

	Функция принимает id проекта и возвращает таблицу с именами трёх сотрудников, которые залогировали 
	максимальное количество часов в этом проекте. Результирующая таблица состоит из двух полей: 
	имени сотрудника и количества часов, отработанных на проекте.
*/
CREATE OR REPLACE FUNCTION best_project_workers(
	p_project_id UUID	
)
RETURNS TABLE (employee TEXT, work_hours INTEGER)
LANGUAGE SQL
AS $$
    SELECT 
		e.name employee, 
		SUM(work_hours) work_hours
	FROM employees e 
	JOIN logs l ON l.employee_id  = e.id
	JOIN projects p ON l.project_id = p.id
    WHERE l.project_id = p_project_id
	GROUP BY e.name
	ORDER BY work_hours DESC
	LIMIT 3;
$$;

SELECT employee, work_hours FROM best_project_workers(
    '2dfffa75-7cd9-4426-922c-95046f3d06a0' -- Project UUID
);

/*
	Задание 7.
	К вам заглянул утомлённый главный бухгалтер Марк Захарович с лёгкой синевой под глазами и попросил как-то 
	автоматизировать расчёт зарплаты, пока бухгалтерия не испустила дух.

	Напишите для бухгалтерии функцию calculate_month_salary для расчёта зарплаты за месяц.

	Функция принимает в качестве параметров даты начала и конца месяца и возвращает результат в виде таблицы с четырьмя полями: 
	id (сотрудника), 
	employee (имя сотрудника), 
	worked_hours и 
	salary.

	Процедура суммирует все залогированные часы за определённый месяц и умножает на актуальную почасовую ставку сотрудника. 
	Исключения — записи с флажками required_review и is_paid.
	
	Если суммарно по всем проектам сотрудник отработал более 160 часов в месяц, все часы свыше 160 оплатят с коэффициентом 1.25.
*/

CREATE OR REPLACE FUNCTION calculate_month_salary(
	p_date_start DATE,
	p_date_end DATE
)
RETURNS TABLE ( id UUID,  employee TEXT, work_hours INTEGER, salary INTEGER)
LANGUAGE SQL
AS $$
	SELECT 
		e.id,
		e.name employee,
		SUM(work_hours) work_hours,
		CASE
			WHEN SUM(work_hours) > 160 THEN (SUM(work_hours) - 160) * e.rate * 1.25 + 160 * rate
 			ELSE SUM(work_hours) * e.rate
		END salary
	FROM logs l
	JOIN employees e ON e.id = l.employee_id
	WHERE 
		work_date BETWEEN p_date_start AND p_date_end
		AND required_review = false
		AND is_paid = false
	GROUP BY e.id
$$;

SELECT * FROM calculate_month_salary(
    '2023-10-01',  -- start of month
    '2023-10-31'   -- end of month
);

