module BaseDocumentStore
include("Utils.jl")
using Base.Filesystem

# TODO: Define how to signal in the index that a document is deleted, something like a negative offset.
const DocID = Int64
const DocPosition = Int64
const DocLength = Int64
const Document = Vector{UInt8}

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

"""
Internal help function used to acquire the read lock on a file.
Can be used with a function accepting a file descriptor.
"""
function with_read_lock(f::Function, docdb::DocDatabase, subpath::String)
    @ensure !docdb.closed error("DocDB was closed before the request could be completed.")
    if !(subpath in keys(docdb.read_locks))
        lock(docdb.global_lock) do
            if !(subpath in keys(docdb.read_locks))
                docdb.read_locks[subpath] = ReentrantLock()
            end
        end
    end
    # Now we need to acquire the read lock, open the file stream (maybe) and return
    # it to the function f.
    return lock(docdb.read_locks[subpath]) do
        if !(subpath in keys(docdb.file_streams))
            docdb.file_streams[subpath] = open(joinpath(docdb.root_path, subpath), "w+")
        end
        return f(docdb.file_streams[subpath])
    end
end

"""
Internal help function used to acquire the write lock on a file stream (after acquiring the read lock).
Can be used with a function accepting a file descriptor.
"""
function with_write_lock(f::Function, docdb::DocDatabase, subpath::String)
    @ensure !docdb.closed error("DocDB was closed before the request could be completed.")
    if !(subpath in keys(docdb.write_locks))
        lock(docdb.global_lock) do
            if !(subpath in keys(docdb.write_locks))
                docdb.write_locks[subpath] = ReentrantLock()
            end
        end
    end
    # Now that we have created it we need to first acquire the read lock to stop reads
    # then to acquire the write lock, then to execute the function f.
    return with_read_lock(docdb, subpath) do fio
        return lock(docdb.write_locks[subpath]) do
            return f(fio)
        end
    end
end
    
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
    end
    return true
end

function docdb_table_insert(docdb::DocDatabase, table_name::String, document::Document) :: DocID
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    return with_write_lock(docdb, table_name * ".index") do index_io
        return with_write_lock(docdb, table_name * ".table") do table_io
            seekend(table_io)
            curpos = DocPosition(position(table_io))
            doclen = DocLength(size(document)[1])
            written = write(table_io, document)
            @ensure (written == doclen) error("In writing to table $(table_name) a document was not written entirely.")
            # After writing the document, we also need to write its place in the index
            seekend(index_io)
            indexpos = DocID(position(index_io) ÷ (DocPosition.size + DocLength.size))
            @ensure (write(index_io, curpos) + write(index_io, doclen) == DocPosition.size + DocLength.size) error("In writing to index $(table_name) a position was not written fully.")
            return indexpos
        end
    end
end

function docdb_table_retrieve(docdb::DocDatabase, table_name::String, docid::DocID) :: Document
    @ensure !docdb.will_close error("DocDB is closing. No more requests are accepted")
    return with_read_lock(docdb, table_name * ".index") do index_io
        return with_read_lock(docdb, table_name * ".table") do table_io
            seek(index_io, docid * (DocPosition.size + DocLength.size))
            document_start = read(index_io, DocPosition)
            document_length = read(index_io, DocLength)
            seek(table_io, document_start)
            return read(table_io, document_length; all=true)
        end
    end
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
