truncate table zabbix."Системы";

insert into zabbix."Системы"
(hostid, groupid, "Система", "Группа систем")
select distinct h.hostid, h.groupid, s.name as "Система", g.name as "Группа систем"
from zabbix.hosts_groups h 
join zabbix.hosts s on h.hostid=s.hostid
join zabbix.hstgrp g on h.groupid=g.groupid;

truncate table zabbix."Ответственность";

insert into zabbix."Ответственность"
(groupid, pid, "ТН", "ФИО", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4")
with 
struct as (
  select distinct pid, "Код подразделения", "ТН", "ФИО", "Подразделение 0", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4" 
  from (
	select pid, left("Код подразделения",2)||'.00.00.00' as "Код подразделения", "ТН", "ФИО", "Подразделение 0", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4" 
	from boss.employees where left("Код подразделения",2)='12' and "Статус"='Работает'
	union all 
	select pid, left("Код подразделения",5)||'.00.00' as "Код подразделения", "ТН", "ФИО", "Подразделение 0", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4" 
	from boss.employees where left("Код подразделения",2)='12' and "Статус"='Работает'
	union all 
	select pid, left("Код подразделения",8)||'.00' as "Код подразделения", "ТН", "ФИО", "Подразделение 0", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4" 
	from boss.employees where left("Код подразделения",2)='12' and "Статус"='Работает'
	union all 
	select pid, "Код подразделения", "ТН", "ФИО", "Подразделение 0", "Подразделение 1", "Подразделение 2", "Подразделение 3", "Подразделение 4" 
	from boss.employees where left("Код подразделения",2)='12' and "Статус"='Работает'
  ) t
)
select distinct g.groupid, t.pid, t."ТН", t."ФИО"
,coalesce(t."Подразделение 1",t."Подразделение 0") as "Подразделение 1"
,coalesce(t."Подразделение 2",t."Подразделение 1",t."Подразделение 0") as "Подразделение 2"
,coalesce(t."Подразделение 3",t."Подразделение 2",t."Подразделение 1",t."Подразделение 0") as "Подразделение 3"
,coalesce(t."Подразделение 4",t."Подразделение 3",t."Подразделение 2",t."Подразделение 1",t."Подразделение 0") as "Подразделение 4"
from (
  select o."Группа хостов", s.pid, s."ТН", s."ФИО", s."Подразделение 0", s."Подразделение 1", s."Подразделение 2", s."Подразделение 3", s."Подразделение 4" 
  from zabbix.responsibility o
  join struct s on s."Код подразделения"=o."Подразделение"
  where o."Подразделение">''
  union all 
  select o."Группа хостов", e.pid, e."ТН", e."ФИО", e."Подразделение 0", e."Подразделение 1", e."Подразделение 2", e."Подразделение 3", e."Подразделение 4" 
  from zabbix.responsibility o
  join boss.employees e on e."ТН"=o."Руководитель"
  where o."Руководитель">''
  union all 
  select o."Группа хостов", s.pid, s."ТН", s."ФИО", s."Подразделение 0", s."Подразделение 1", s."Подразделение 2", s."Подразделение 3", s."Подразделение 4" 
  from ( --Группы без назначенных ответственных привязываем на весь ДИТ 12.00.00.00
	select distinct "Группа систем" as "Группа хостов", '12.00.00.00' as "Подразделение", null as "Руководитель" 
	from zabbix."Системы"
	where hostid in (select hostid from zabbix."Системы" where "Группа систем"='SLA')
	and "Группа систем"<>'SLA'
	and "Группа систем" not in (select distinct "Группа хостов" from zabbix.responsibility)
  ) o
  join struct s on s."Код подразделения"=o."Подразделение"
  where o."Подразделение">''
) t join zabbix.hstgrp g  on t."Группа хостов"=g.name;

--Доступность
drop table if exists func;

create temporary table func on commit preserve rows as 
select f.triggerid, max(i.hostid) as hostid
from zabbix.functions f 
join zabbix.items i  on i.itemid=f.itemid
group by f.triggerid;

drop table if exists trig;

create temporary table trig on commit preserve rows as 
select 
 triggerid
,max(case when tag='scope' and value='availability' then 'Да' end) as scope_availability
from zabbix.trigger_tag 
group by triggerid;

drop table if exists cal;

create temporary table cal on commit preserve rows as 
select 
 day as DateID, day::timestamptz as fd, day::timestamptz + interval '86399 seconds' as td
from calendar
where day between '2022-04-01'::date and now();

create index cal_fd_td on cal using btree (fd, td);

drop table if exists evnts;

create temporary table evnts on commit preserve rows as 
select 
 t.objectid, t.eventid, t.value, t.severity, t.fd, t.td
from (
  select
   objectid, eventid, value, severity, to_timestamp(clock) as fd
  ,least(
		to_timestamp(clock) + interval '3 month',
		coalesce(to_timestamp(lead(clock)over(partition by objectid order by eventid)-1),now())
  ) as td
  from zabbix.events e 
) t join zabbix.triggers p on t.objectid=p.triggerid 
where fd<td;

drop table if exists evnts1;

create temporary table evnts1 on commit preserve rows as 
select
 h.triggerid, h.hostid, e.eventid as "ИД события", e.fd, e.td
,case e.severity
		when 1 then '1 - Information'
		when 2 then '2 - Low'
		when 3 then '3 - Average'
		when 4 then '4 - High'
		when 5 then '5 - Critical'
		else '0 - N/A'
 end as "Тяжесть"
,case scope_availability when 'Да' then 1 else 0 end as "Стоимость"
,'Offline' as "Статус"
,0 as "Общее время"
from evnts e 
join func h on e.objectid=h.triggerid 
left join trig tt on e.objectid=tt.triggerid 
where e.value=1 and e.severity>0;

create index evnts1_fd_td on evnts1 using btree (fd, td);

drop table if exists evnts2;

create temporary table evnts2 on commit preserve rows as 
select distinct
 h.hostid, e.fd, e.td
,null::int8 as triggerid
,null::int8 as "ИД события"
,null::varchar(50) as "Тяжесть"
,null::int as "Стоимость"
,'Online' as "Статус"
from (
	select objectid, min(fd) as fd, max(td) as td
	from evnts e
	group by objectid
) e 
join func h on e.objectid=h.triggerid;

create index evnts2_fd_td on evnts2 using btree (fd, td);

drop table if exists res;

create temporary table res on commit preserve rows as 
select
 d.DateID, e.triggerid, e.hostid, e."ИД события", e."Тяжесть", e."Стоимость", e."Статус", e."Общее время"
,case when e.fd>d.fd then e.fd else d.fd end as "Время начала"
,case when e.td<d.td then e.td else d.td end as "Время окончания"
from evnts1 e 
join cal d on d.fd<=e.td and d.td>e.fd
union all 
select distinct
 d.DateID, e.triggerid, e.hostid, e."ИД события", e."Тяжесть", e."Стоимость", e."Статус"
,extract(epoch from case when d.td>now() then now() else d.td end)-extract(epoch from d.fd)+1 as "Общее время"
,d.fd as "Время начала"
,case when d.td>now() then now() else d.td end as "Время окончания"
from evnts2 e 
join cal d on d.fd<=e.td and d.td>e.fd;

truncate table zabbix."Доступность";

insert into zabbix."Доступность"
("День", "Тригер", hostid, "ИД события", "Статус", "Время начала", "Время окончания", "Общее время", "Время недоступности", "Тяжесть", "Стоимость", "Цена недоступности")
select
 t.DateID, coalesce(d.description,'ДОСТУПНО') as "Тригер", t.hostid, t."ИД события", t."Статус", t."Время начала", t."Время окончания", t."Общее время"
,case when t."Статус"='Offline' then extract(epoch from t."Время окончания")-extract(epoch from t."Время начала")+1 end as "Время недоступности"
,t."Тяжесть", t."Стоимость"
,t."Стоимость"*case when t."Статус"='Offline' then extract(epoch from t."Время окончания")-extract(epoch from t."Время начала")+1 end as "Цена недоступности"
from res t
left join zabbix.triggers d on t.triggerid=d.triggerid
where t.hostid in (
	select h.hostid
	from zabbix.hosts_groups h 
	where h.groupid=201 --SLA
)
and t.hostid in (
  select distinct h.hostid
  from zabbix.hosts_groups h 
  join zabbix.hstgrp g on h.groupid=g.groupid
  where g.name in (select distinct "Группа хостов" from zabbix.responsibility)
);