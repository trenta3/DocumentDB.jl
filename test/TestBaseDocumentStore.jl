@testset "Base Store Usage" begin
    # Some tests that a standard table usage goes smoothly
    temporary_directory = mktempdir()
    @info "Created a new temporary directory for testing" temporary_directory
    db = docdb_open(temporary_directory)

    # First we create the table and check it is there
    @test_nowarn docdb_table_create(db, "main")
    @test size(docdb_list_tables(db))[1] == 1
    @test docdb_list_tables(db)[1] == TableInfo("main")
    @test docdb_table_create(db, "main") == false
    @test size(docdb_list_tables(db))[1] == 1
    @test docdb_list_tables(db)[1] == TableInfo("main")
    @test_nowarn docdb_table_create(db, "main"; exists_ok=true)
    @test size(docdb_list_tables(db))[1] == 1
    @test docdb_list_tables(db)[1] == TableInfo("main")

    document1 = Vector{UInt8}(transcode(UInt8, "A Simple string with some unicode: α → ∞."))
    docid1 = docdb_record_insert(db, "main", document1)
    @test docid1 == DocID(0)
    document2 = Vector{UInt8}(transcode(UInt8, "This time: ∫ α^3 + f(β) dβ"))
    docid2 = docdb_record_insert(db, "main", document2)
    @test docid2 == DocID(1)
    @test docdb_record_insert(db, "main", document1) == DocID(2)
    @test docdb_record_retrieve(db, "main", DocID(0)) == document1
    @test docdb_record_retrieve(db, "main", DocID(1)) == document2
    @test docdb_record_retrieve(db, "main", DocID(2)) == document1

    @test docdb_record_erase(db, "main", DocID(0))
    @test docdb_record_erase(db, "main", DocID(0)) == false
    @test docdb_record_retrieve(db, "main", DocID(0)) == nothing
    @test docdb_record_retrieve(db, "main", DocID(1)) == document2

    @test_nowarn docdb_close(db)
end
