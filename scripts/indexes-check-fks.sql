create or replace view info.fk_indexes_check as
with existing_indexes as (
	select 
		s.nspname as schema,
		t.relname as table_name,
		i.relname as index_name,
		array_to_string(array_agg(a.attname), ', ') as column_names,
		x.indrelid as oid_table, /* The OID of the pg_class entry for the table this index is for */
		string_to_array(x.indkey[0]::text, ' ')::smallint[] as column_1st_index_key
	from pg_catalog.pg_class i
	inner join pg_catalog.pg_namespace s 
		on s.oid = i.relnamespace
	inner join pg_catalog.pg_index x 
		on x.indexrelid = i.oid
	inner join pg_catalog.pg_class t 
		on t.oid = x.indrelid 
	inner join pg_catalog.pg_attribute a 
		on a.attrelid = t.oid 
		and a.attnum = any(x.indkey)
	where i.relkind = 'i'
	and t.relkind = 'r'
	and s.nspname not in ('pg_catalog','pg_toast')
	group by s.nspname, t.relname, i.relname, x.indrelid, x.indkey
)
select 
	child_schema, 
	child_table, 
	child_column, 
	table_rows,
	fk_name
	parent_schema,
	parent_table,
	parent_column,
	existing_index,
	case
		when existing_index is null 
		then concat('CREATE INDEX ',child_table,'_',child_column,'__idx ON ',child_schema,'.',child_table,' USING btree (',child_column,');')
		else null 
	end as new_index
from (
	select 
		fk.child_schema, 
		fk.child_table, 
		ac.attname child_column,
		fk.table_rows,
		pn.nspname as parent_schema,
		pt.relname as parent_table,
		ap.attname parent_column,
		fk.fk_name,
		e.index_name as existing_index
	from (
		select
		s.nspname as child_schema,
		t.relname as child_table,
		t.reltuples::bigint as table_rows, /* number of table rows :: statistics updated by VACUUM and ANALYZE */
		c.conname as fk_name,
		unnest(c.conkey) as child_col, /* smallint[] ::  If a table constraint (including foreign keys, but not constraint triggers), list of the constrained columns */	
		unnest(c.confkey) as parent_col, /* smallint[] ::  If a foreign key, list of the referenced columns */
		c.conrelid as child_tbl, /* (child) The table this constraint is on; 0 if not a table constraint */
		c.confrelid as parent_tbl, /* (parent) If a foreign key, the referenced table; else 0 */
		c.conkey as child_col_array
		from pg_catalog.pg_constraint c
		inner join pg_catalog.pg_namespace s
			on s.oid = c.connamespace
		inner join pg_catalog.pg_class t
			on t.oid = c.conrelid
			and t.relnamespace = s.oid
		where c.contype = 'f' /* foreign key constraint */
		and s.nspname not in ('pg_catalog','pg_toast')
	) fk
	inner join pg_catalog.pg_attribute ac /* child attributes */
		on ac.attrelid = fk.child_tbl 
		and ac.attnum = fk.child_col
	inner join pg_catalog.pg_class pt /* parent table */
		on pt.oid = fk.parent_tbl
	inner join pg_catalog.pg_namespace pn /* parent schema */
		on pn.oid = pt.relnamespace
	inner join pg_catalog.pg_attribute ap /* parent attributes */
		on ap.attrelid = fk.parent_tbl 
		and ap.attnum = fk.parent_col
	left join existing_indexes e
		on e.oid_table = fk.child_tbl 
		and e.column_1st_index_key = fk.child_col_array
) x /*where table_rows > 0 and existing_index is null */
order by table_rows desc, child_schema, child_table, child_column;

seaber=# 
\d info.fk_indexes_check

               View "info.fk_indexes_check"

     Column     |  Type  | Collation | Nullable | Default 
----------------+--------+-----------+----------+---------
 child_schema   | name   |           |          | 
 child_table    | name   |           |          | 
 child_column   | name   |           |          | 
 table_rows     | bigint |           |          | 
 parent_schema  | name   |           |          | 
 parent_table   | name   |           |          | 
 parent_column  | name   |           |          | 
 existing_index | name   |           |          | 
 new_index      | text   |           |          | 

select * from info.fk_indexes_check where existing_index is null;

