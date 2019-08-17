declare @tablename varchar(100);
set @tablename='PeopleJob'


SELECT
    i.[name] AS IndexName,
    t.[name] AS TableName,
    SUM(s.[used_page_count]) * 8/1024 AS IndexSizeMB
into #i1
FROM sys.dm_db_partition_stats AS s
INNER JOIN sys.indexes AS i ON s.[object_id] = i.[object_id] 
    AND s.[index_id] = i.[index_id]
INNER JOIN sys.tables t ON t.OBJECT_ID = i.object_id
WHERE OBJECT_NAME(t.OBJECT_ID)=@tablename
GROUP BY i.[name], t.[name]


select SCHEMA_NAME (o.SCHEMA_ID) SchemaName
   ,o.name ObjectName,i.name IndexName
   ,i.type_desc
   ,LEFT(list, ISNULL(splitter-1,len(list))) as Columns
   , SUBSTRING(list, indCol.splitter +1, 500) as includedColumns
into #i2
from sys.indexes i
join sys.objects o on i.object_id = o.object_id
cross apply (select NULLIF(charindex('|',indexCols.list),0) splitter , list
              from (select cast((
                           select case when sc.is_included_column = 1 and sc.ColPos = 1 then '|' else '' end +
                                  case when sc.ColPos  > 1 then ', ' else '' end + name
                             from (select sc.is_included_column, index_column_id, name
                                        , ROW_NUMBER() over (partition by sc.is_included_column
                                                             order by sc.index_column_id) ColPos
                                    from sys.index_columns  sc
                                    join sys.columns        c on sc.object_id = c.object_id
                                                             and sc.column_id = c.column_id
                                   where sc.index_id = i.index_id
                                     and sc.object_id = i.object_id ) sc
                    order by sc.is_included_column
                            ,ColPos
                      for xml path (''), type) as varchar(max)) list)indexCols ) indCol
where o.name=@tablename
order by SchemaName, ObjectName, IndexName


SELECT OBJECT_NAME(i.[object_id]) AS [ObjectName], i.name AS [IndexName],
       s.user_seeks, s.user_scans, s.user_lookups,
	   s.user_seeks + s.user_scans + s.user_lookups AS [Total Reads], 
	   s.user_updates AS [Writes],  
	   i.type_desc AS [Index Type], i.fill_factor AS [Fill Factor],
	   s.last_user_scan, s.last_user_lookup, s.last_user_seek
into #i3
FROM sys.indexes AS i WITH (NOLOCK)
LEFT OUTER JOIN sys.dm_db_index_usage_stats AS s WITH (NOLOCK)
ON i.[object_id] = s.[object_id]
AND i.index_id = s.index_id
AND s.database_id = DB_ID()
WHERE OBJECTPROPERTY(i.[object_id],'IsUserTable') = 1
AND OBJECT_NAME(i.[object_id]) =@tablename
ORDER BY s.user_seeks + s.user_scans + s.user_lookups DESC OPTION (RECOMPILE); 


select i1.TableName,i1.IndexName,i1.IndexSizeMB
	,i2.type_desc,i2.Columns,i2.includedColumns
	,i3.[Total Reads],i3.Writes,i3.user_scans,i3.user_seeks
	,i3.user_lookups,i3.last_user_scan,i3.last_user_seek,i3.last_user_lookup
	,i3.[Fill Factor]
from #i1 as i1
inner join #i2 as i2 on i1.IndexName=i2.IndexName
inner join #i3 as i3 on i1.IndexName=i3.IndexName
order by i3.user_seeks asc


drop table  #i1
drop table  #i2
drop table  #i3