macro ensure(condexpr, otherexpr)
    expr = quote
        if !($(esc(condexpr)))
            $(esc(otherexpr))
        end
    end
    return expr
end

macro test(condexpr, thenexpr)
    expr = quote
        if ($(esc(condexpr)))
            $(esc(thenexpr))
        end
    end
    return expr
end
