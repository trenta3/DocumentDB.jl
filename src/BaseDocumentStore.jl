module BaseDocumentStore
include("Utils.jl")
using Base.Filesystem

# TODO: Define how to signal in the index that a document is deleted, something like a negative offset.
const DocID = Int64
const DocPosition = Int64
const DocLength = Int64
const Document = Vector{UInt8}
const Nullable{T} = Union{Nothing, T}

mutable struct DocDatabase
    root_path::AbstractString
    will_close::Bool
    closed::Bool
    global_lock::ReentrantLock
    write_locks::Dict{String, ReentrantLock}
    read_locks::Dict{String, ReentrantLock}
    file_streams::Dict{String, IOStream}
end
DocDatabase(root_path) = DocDatabase(root_path, false, false, ReentrantLock(), Dict{String, ReentrantLock}(), Dict{String, ReentrantLock}(), Dict{String, IOStream}())

struct TableInfo
    table_name::String
end

include("RWUtils.jl")

"""
Opens a folder (or creates it if it does not exist) and starts a document database in it.
"""
function docdb_open(root_path::AbstractString; create::Bool=true) :: DocDatabase
    @test (create && !ispath(root_path)) mkpath(root_path)
    @ensure isdir(root_path) error("Passed path $(root_path) is not a directory!")
    return DocDatabase(root_path)
end

"""
Lists existing tables in a database.
"""
function docdb_list_tables(docdb::DocDatabase) :: Vector{TableInfo}
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    return [
        TableInfo(split(filename, ".")[1])
        for filename in readdir(docdb.root_path)
        if split(filename, ".")[end] == "table"
    ]
end

"""
Creates a table in a database.
"""
function docdb_table_create(docdb::DocDatabase, table_name::String; exists_ok::Bool=false) :: Bool
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    table_path = joinpath(docdb.root_path, table_name * ".table")
    index_path = joinpath(docdb.root_path, table_name * ".index")
    if ispath(table_path)
        @ensure exists_ok return false
    else
        touch(table_path)
        touch(index_path)
        # Write our custom signature at start of the table
        _table_write(docdb, table_name, Vector{UInt8}(transcode(UInt8, "DOCDBTBL")), DocPosition(0))
    end
    return true
end

"""
Insert a record in the storage
"""
function docdb_record_insert(docdb::DocDatabase, table_name::String, document::Document) :: DocID
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    (doc_pos, doc_len) = _table_write(docdb, table_name, document)
    @ensure (doc_len == size(document)[1]) error("In writing to table $(table_name) a document was not written entirely.")
    docid = _index_write(docdb, table_name, doc_pos, doc_len)
    return docid
end

"""
Wipe a record from storage, deleting it also from the index.

> This operation is destructive. Be careful!
"""
function docdb_record_erase(docdb::DocDatabase, table_name::String, docid::DocID) :: Bool
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    index = _index_read(docdb, table_name, docid)
    @test (index == nothing) return false
    (docpos, doclen) = index
    _table_write(docdb, table_name, repeat(UInt8[0], doclen), docpos)
    _index_write(docdb, table_name, 0, 0, docid)
    return true
end

"""
Try to retrieve a document from the storage given its ID.
It returns nothing if fails.
"""
function docdb_record_retrieve(docdb::DocDatabase, table_name::String, docid::DocID) :: Nullable{Document}
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    index = _index_read(docdb, table_name, docid)
    @test (index == nothing) return nothing
    (docpos, doclen) = index
    return _table_read(docdb, table_name, docpos, doclen)
end

"""
Closes all open resources of a document database, ensuring that no further requests can be made to the database.
"""
function docdb_close(docdb::DocDatabase; grace_time=5.0) :: Nothing
    # We first acquire all existing write locks, then close the file_streams
    lock(docdb.global_lock) do
        # Start rejecting new requests
        docdb.will_close = true
        # Give time to existing requests to terminate gracefully
        sleep(grace_time)
        # Acquire all existing locks
        for (filename, rlock) in docdb.read_locks
            lock(rlock)
        end
        for (filename, wlock) in docdb.write_locks
            lock(wlock)
        end
        # Finally set the database to closed
        docdb.closed = true
        # Now close all open file descriptor
        for (filename, fio) in docdb.file_streams
            close(fio)
        end
        for (filename, wlock) in docdb.write_locks
            unlock(wlock)
        end
        for (filename, rlock) in docdb.read_locks
            unlock(rlock)
        end
    end
    return nothing
end
end # module
