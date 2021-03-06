import
    ast, typetraits, sequtils, strformat, typetraits, tables, strutils,
    ../lexer/lexer, ../lexer/token


type
    Parser* = ref object of RootObj
        l: Lexer
        curToken: Token
        peekToken: Token
        errors*: seq[string]


proc tokenToPrecedence(tok: Token): Precedence

proc newParser*(l: Lexer): Parser
proc nextToken(self: Parser)
proc curTokenIs(self: Parser, t: TokenType): bool
proc peekTokenIs(self: Parser, t: TokenType): bool
proc expectPeek(self: Parser, t: token.TokenType): bool
proc peekPrecedence(self: Parser): Precedence
proc curPrecedence(self: Parser): Precedence

proc parseLetStatement(self: Parser): PNode
proc parseReturnStatement(self: Parser): PNode

proc parseIdentifier(self: Parser): PNode
proc parseIntegerLiteral(self: Parser): PNode
proc parseStringLiteral(self: Parser): PNode
proc parseBoolean(self: Parser): PNode
proc parseGroupedExpression(self: Parser): PNode
proc parseIfExpression(self: Parser): PNode
proc parseFunctionLiteral(self: Parser): PNode
proc parseArrayLiteral(self: Parser): PNode
proc parseFunctionParameters(self: Parser): seq[PNode]
proc parseCallExpression(self: Parser, function: PNode): PNode
proc parseExpressionList(self: Parser, endToken: token.TokenType): seq[PNode]
proc parseBlockStatement(self: Parser): BlockStatements
proc parseIndexExpression(self: Parser, left: PNode): PNode

proc parsePrefixExpression(self: Parser): PNode
proc parseInfixExpression(self: Parser, left: PNode): PNode

proc parseExpressionStatement(self: Parser): PNode
proc parseStatement(self: Parser): PNode
proc parseExpression(self: Parser, precedence: Precedence): PNode

proc parseProgram*(self: Parser): PNode
proc error*(self: Parser): seq[string]
proc noPrefixParseError(self: Parser)
proc peekError(self: Parser, t: token.TokenType)



# implementation


proc tokenToPrecedence(tok: Token): Precedence =
    case tok.Type
    of LBRACKET: return Precedence.Index
    of LPAREN: return Precedence.Call
    of SLASH, ASTERISC: return Precedence.Product
    of PLUS, MINUS: return Precedence.Sum
    of LT, GT: return Precedence.Lg
    of EQ, NOT_EQ: return Precedence.Equals
    else: return Precedence.Lowest


proc newParser*(l: Lexer): Parser =
    result = Parser(l: l, errors: newSeq[string]())
    result.nextToken()
    result.nextToken()


proc nextToken(self: Parser) =
    self.curToken = self.peekToken
    self.peekToken = self.l.nextToken()


proc curTokenIs(self: Parser, t: TokenType): bool =
    self.curToken.Type == t


proc peekTokenIs(self: Parser, t: TokenType): bool =
    self.peekToken.Type == t


proc expectPeek(self: Parser, t: token.TokenType): bool =
    if self.peekTokenIs(t):
        self.nextToken()
        return true

    self.peekError(t)
    return false


proc curPrecedence(self: Parser): Precedence = tokenToPrecedence(self.curToken)


proc peekPrecedence(self: Parser): Precedence = tokenToPrecedence(self.peekToken)



# parse


proc parseLetStatement(self: Parser): PNode =
    let statement = PNode(kind: nkLetStatement, Token: self.curToken)

    # ident
    if not self.expectPeek(token.IDENT):
        return PNode(kind: Nil)

    statement.LetName = PNode(
                            kind: nkIdent,
                            Token: self.curToken,
                            IdentValue: self.curToken.Literal)

    if not self.expectPeek(token.ASSIGN):
        return nil

    self.nextToken()
    statement.LetValue = self.parseExpression(Lowest)
    if self.peekTokenIs(SEMICOLON):
        self.nextToken()

    statement


proc parseReturnStatement(self: Parser): PNode =
    let statement = PNode(kind: nkReturnStatement, Token: self.curToken)
    self.nextToken()
    statement.ReturnValue = self.parseExpression(Lowest)

    if self.peekTokenIs(SEMICOLON):
        self.nextToken()

    statement


proc parseIdentifier(self: Parser): PNode =
    PNode(
        kind: nkIdent,
        Token: self.curToken,
        IdentValue: self.curToken.Literal)


proc parseIntegerLiteral(self: Parser): PNode =
    PNode(
        kind: nkIntegerLiteral,
        Token: self.curToken,
        IntValue: self.curToken.Literal.parseInt)


proc parseStringLiteral(self: Parser): PNode =
    PNode(
        kind: nkStringLiteral,
        Token: self.curToken,
        StringValue: self.curToken.Literal)


proc parseBoolean(self: Parser): PNode =
    PNode(
        kind: nkBoolean,
        Token: self.curToken,
        BlValue: self.curTokenIs(token.TRUE))


proc parseGroupedExpression(self: Parser): PNode =
    self.nextToken()
    result = self.parseExpression(Lowest)
    if not self.expectPeek(RPAREN): return nil


proc parseIfExpression(self: Parser): PNode =
    result = PNode(
                kind: nkIFExpression,
                Token: self.curToken)

    if not self.expectPeek(LPAREN): return nil
    self.nextToken()
    result.Condition = self.parseExpression(Lowest)

    if not self.expectPeek(RPAREN): return nil
    if not self.expectPeek(LBRACE): return nil

    result.Consequence = self.parseBlockStatement()

    if self.peekTokenIs(ELSE):
        self.nextToken()
        if not self.expectPeek(LBRACE): return nil
        result.Alternative = self.parseBlockStatement()


proc parseFunctionLiteral(self: Parser): PNode =
    result = PNode(
                kind: nkFunctionLiteral,
                Token: self.curToken)

    if not self.expectPeek(LPAREN): return nil
    result.FnParameters = self.parseFunctionParameters()

    if not self.expectPeek(LBRACE): return nil
    result.FnBody = self.parseBlockStatement()


proc parseArrayLiteral(self: Parser): PNode =
    result = PNode(
                kind: nkArrayLiteral,
                Token: self.curToken)
    result.ArrayElem = self.parseExpressionList(RBRACKET)


proc parseFunctionParameters(self: Parser): seq[PNode] =
    var identifiers = newSeq[PNode]()
    if self.peekTokenIs(RPAREN):
        self.nextToken()
        return identifiers

    self.nextToken()
    var ident = PNode(
                    kind: nkIdent,
                    Token: self.curToken,
                    IdentValue: self.curToken.Literal)
    identifiers.add(ident)

    while self.peekTokenIs(COMMA):
        self.nextToken()
        self.nextToken()
        ident = PNode(
                    kind: nkIdent,
                    Token: self.curToken,
                    IdentValue: self.curToken.Literal)
        identifiers.add(ident)

    if not self.expectPeek(RPAREN): return
    identifiers


proc parseCallExpression(self: Parser, function: PNode): PNode =
    result = PNode(
                kind: nkCallExpression,
                Token: self.curToken,
                Function: function)
    self.nextToken()
    result.Args = self.parseExpressionList(RPAREN)


proc parseExpressionList(self: Parser, endToken: token.TokenType): seq[PNode] =
    var l = newSeq[PNode]()
    if self.peekTokenIs(endToken):
        self.nextToken()
        return l

    self.nextToken()
    l.add(self.parseExpression(Precedence.Lowest))

    while self.peekTokenIs(COMMA):
        self.nextToken()
        self.nextToken()
        l.add(self.parseExpression(Precedence.Lowest))

    if not self.expectPeek(endToken): return
    l


proc parseBlockStatement(self: Parser): BlockStatements =
    result = BlockStatements(Token: self.curToken)
    result.Statements = newSeq[PNode]()

    self.nextToken()
    while not self.curTokenIs(RBRACE) and not self.curTokenIs(EOF):
        let statement = self.parseStatement()
        if statement != nil:
            result.Statements.add(statement)
        self.nextToken()


proc parseIndexExpression(self: Parser, left: PNode): PNode =
    result = PNode(
                kind: nkIndexExpression,
                Token: self.curToken,
                ArrayLeft: left)

    self.nextToken()
    result.ArrayIndex = self.parseExpression(Lowest)
    if not self.curTokenIs(RBRACKET): return nil


proc parsePrefixExpression(self: Parser): PNode =
    let
        operator = self.curToken.Type
        prefix = self.curToken
    self.nextToken()

    let right = self.parseExpression(Precedence.Prefix)
    PNode(
        kind: nkPrefixExpression,
        Token: prefix,
        PrOperator: operator,
        PrRight: right
    )


proc parseInfixExpression(self: Parser, left: PNode): PNode =
    let
        operator = self.curToken.Type
        p = self.curPrecedence()
    self.nextToken()

    let right = self.parseExpression(p)
    PNode(
        kind: nkInfixExpression,
        Token: self.curToken,
        InOperator: operator,
        InLeft: left,
        InRight: right
    )


proc parseExpression(self: Parser, precedence: Precedence): PNode =
    # prefix
    var left: PNode
    case self.curToken.Type
    of IDENT:
        left = self.parseIdentifier()
    of INT:
        left = self.parseIntegerLiteral()
    of STRING:
        left = self.parseStringLiteral()
    of TRUE, FALSE:
        left = self.parseBoolean()
    of BANG, MINUS:
        left = self.parsePrefixExpression()
    of LPAREN:
        left = self.parseGroupedExpression()
    of IF:
        left = self.parseIfExpression()
    of FUNCTION:
        left = self.parseFunctionLiteral()
    of LBRACKET:
        left = self.parseArrayLiteral()
    else:
        self.noPrefixParseError()
        left = nil

    # infix
    while precedence < self.peekPrecedence() and not self.peekTokenIs(SEMICOLON):
        case self.peekToken.Type
        of PLUS, MINUS, SLASH, ASTERISC, EQ, NOT_EQ, LT, GT:
            self.nextToken()
            left = self.parseInfixExpression(left)
        of LPAREN:
            left = self.parseCallExpression(left)
        of LBRACKET:
            left = self.parseIndexExpression(left)
        else:
            return left

    return left


proc parseExpressionStatement(self: Parser): PNode =
    result = self.parseExpression(Precedence.Lowest)
    if self.peekTokenIs(SEMICOLON):
        self.nextToken()


proc parseStatement(self: Parser): PNode =
    case self.curToken.Type
    of LET:
        return self.parseLetStatement()
    of RETURN:
        return self.parseReturnStatement()
    else:
        return self.parseExpressionStatement()



# create AST Root Node

proc parseProgram*(self: Parser): PNode =
    result = PNode(kind: Program)
    result.statements = newSeq[PNode]()

    while self.curToken.Type != token.EOF:
        let statement = self.parseStatement()
        result.statements.add(statement)
        self.nextToken()



# Errors


proc error*(self: Parser): seq[string] = self.errors


proc noPrefixParseError(self: Parser) =
    self.errors.add(fmt"no prefix parse function for {self.curToken.Type}")


proc peekError(self: Parser, t: token.TokenType) =
    let msg = fmt"expected next token to be {t}, got {self.peekToken.Type} instead"
    self.errors.add(msg)


proc main() = discard
when isMainModule:
    main()
