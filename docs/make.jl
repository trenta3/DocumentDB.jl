using Documenter, DocumentDB

makedocs(;
    modules=[DocumentDB],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
        "Basic Store" => "basicstore.md",
    ],
    repo="https://gitlab.com/trenta3/DocumentDB.jl/blob/{commit}{path}#L{line}",
    sitename="DocumentDB.jl",
    authors="Dario Balboni",
    assets=String[],
)
