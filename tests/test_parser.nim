import unittest
import ../src/parser/ast
import ../src/parser/parser
import ../src/lexer/lexer

suite "Parser":
    test "it should parse letStatements":
        let input: string = """
            let x = 5;
            let y = 10;
            let foobar = 838383;\0
        """

        let l = newLexer(input)
        let p = newParser(l)

        let program = p.parseProgram()
        check(program.statements != nil)
        check(program.statements.len == 3)

        let expects = @["x", "y", "foobar"]

        for i in 0..<program.statements.len:
            let statement = program.statements[i]
            check(statement.Name.Value == expects[i])



    # # NOTE: わからん p.38
    # test "it should parse letStatement":
    #     let input: string = """
    #         let x = 5;
    #         let y = 10;
    #         let foobar = 838383;\0
    #     """

    #     let l = newLexer(input)
    #     let p = newParser(l)