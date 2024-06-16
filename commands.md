host.docker.internal user root

docker compose -f stack.yml up --build

docker exec -it postgres_postgis bash

winpty docker exec -it pgadmin4 //bin//sh

find / -name 'sprint_1.sql'

# Directory is optional (defaults to cwd)

/var/lib/pgadmin/storage/lyapindm_yandex.ru/sprint_1.sql

docker cp pgadmin4:/var/lib/pgadmin/storage/lyapindm_yandex.ru/sprint_3.sql C:/Users/Diamond/Desktop/postgreSQL/sprint_3

docker exec -it postgres_15 psql -U root -d sprint_1

```
 \COPY raw_data.sales FROM '/db/cars.csv' WITH DELIMITER AS ',' NULL 'null' CSV HEADER;
```

docker exec -i postgres_15 /bin/bash -c "PGPASSWORD=secret pg_dump --username root game" > ./dump/dump.sql
docker exec -i postgres_15 /bin/bash -c "PGPASSWORD=secret psql --username root game" < ./dump/the_mono.dev.sql

docker exec -i postgres_postgis pg_restore -U postgres -v -d sprint_4_2 < ./dump/project_4_part2.sql
