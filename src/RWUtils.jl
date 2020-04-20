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
Function for internal usage to retrieve the position and length of a document in a table
"""
function _index_read(docdb::DocDatabase, table_name::String, docid::DocID) :: Nullable{Tuple{DocPosition, DocLength}}
    return with_read_lock(docdb, table_name * ".index") do index_io
        seek(index_io, docid * (DocPosition.size + DocLength.size))
        @test eof(index_io) return nothing
        document_start = read(index_io, DocPosition)
        document_length = read(index_io, DocLength)
        @test (document_start == 0) return nothing
        return (document_start, document_length)
    end
end

"""
Function for internal usage to write the position and length of a document in the index.
"""
function _index_write(docdb::DocDatabase, table_name::String, doc_pos::DocPosition, doc_len::DocLength, docid::Nullable{DocID}=nothing) :: DocID
    return with_write_lock(docdb, table_name * ".index") do index_io
        if docid == nothing
            seekend(index_io)
        else
            seek(index_io, docid * (DocPosition.size + DocLength.size))
        end
        current_position = position(index_io)
        write(index_io, doc_pos)
        write(index_io, doc_len)
        return DocID(current_position ÷ (DocPosition.size + DocLength.size))
    end
end

"""
Function for internal usage to retrieve a document from the table.
"""
function _table_read(docdb::DocDatabase, table_name::String, doc_pos::DocPosition, doc_len::DocLength) :: Nullable{Document}
    return with_read_lock(docdb, table_name * ".table") do table_io
        seek(table_io, doc_pos)
        @test eof(table_io) return nothing
        return read(table_io, doc_len; all=true)
    end
end

"""
Function for internal usage to write a document to the table.
"""
function _table_write(docdb::DocDatabase, table_name::String, document::Document, doc_pos::Nullable{DocPosition}=nothing) :: Tuple{DocPosition, DocLength}
    return with_write_lock(docdb, table_name * ".table") do table_io
        if doc_pos == nothing
            seekend(table_io)
        else
            seek(table_io, doc_pos)
        end
        doc_pos = DocPosition(position(table_io))
        doc_len = DocLength(write(table_io, document))
        return (doc_pos, doc_len)
    end
end

