"""
In DocDB a database consists just of tables, which are flat files where new objects are added one after the other, as well as an index file for each table which stores the offsets where new objects start.

BTree structures can also be built on top of these to act as real indexes over tables.
"""
module DocumentDB

include("BaseDocumentStore.jl")
using .BaseDocumentStore: DocID, DocPosition, DocLength, Document, DocDatabase, TableInfo, with_read_lock, with_write_lock, docdb_open, docdb_list_tables, docdb_table_create, docdb_table_insert, docdb_table_retrieve, docdb_close
export DocID, DocPosition, DocLength, Document, DocDatabase, TableInfo, docdb_open, docdb_list_tables, docdb_table_create, docdb_table_insert, docdb_table_retrieve, docdb_close

end # module
