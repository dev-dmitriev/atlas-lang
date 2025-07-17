const std = @import ( "std" );
const mem = std.mem;

const ReservedToken = enum ( u8 ) {  
    Unknown,                      // Token desconhecido 
    Identifier,                   // Variável, rótulo ou subrotina
    NumberLiteral,                // Número literais
    StringLiteral,                // Texto entre aspas
    //CharLiteral,                  // Caractere individual com escape

    //////////////////////////////////////////////////
    ///        KEYWORDS DE FLUXO ADA-LIKE          /// 
    //////////////////////////////////////////////////
    kwModule,                     // Módulos Starndard ATLAS
    kwPackage,                    // Pacote organizacional
    kwProc,                       // Definir uma subrotina
    kwIs,                         // Marcar ínício do corpo da subrotulo/bloco
    kwEnd,                        // Marca fim de bloco/subrotina
    kwCall,                       // Chama uma subrotina 
    kwReturn,                     // Retorna de uma subrotina
    kwIf,                         // Início de uma condição 
    kwThen,                       // Marca bloco condicional verdadeira
    kwLoop,                       // Inicia um laço 
    kwExit,                       // Saída do laço 
    kwWhen,                       // Usado com EXIT para condição 
    kwBlock,                      // Bloco anônimo ( opcional )
                                  
    ////////////////////////////////////////////////
    ///            PILHA ( FORTH-LIKE )          ///
    ////////////////////////////////////////////////
    kwPush,                       // Empilha um literal ou valor
    kwDrop,                       // Remover o topo da pilha 
    kwDup,                        // Duplica o topo da pilha 
    kwSwap,                       // Troca as duas posições do topo 

    ////////////////////////////////////////////////
    ///             ARITMÉTICA/COMPARAÇÃO        /// 
    ////////////////////////////////////////////////
    kwAdd,                         // topo-1 + topo
    kwSub,                         // topo-1 - topo 
    kwMul,                         // topo-1 * topo 
    kwDiv,                         // topo-1 / topo 
    kwEq,                          // topo-1 == topo -> empilha 1 ou 0
    kwGt,                          // topo-1 > topo -> empilha 1 ou 0
    kwLt,                          // topo-1 < topo -> empilha 1 ou 0

    ////////////////////////////////////////////////
    ///          MOVIMENTAÇÃO DE DADOS           ///
    ////////////////////////////////////////////////
    kwSet,                          // Salva topo em variável
    kwGet,                          // Empilha valor de variável

    ////////////////////////////////////////////////
    ///             SÍMBOLO MÍNIMO               ///
    ////////////////////////////////////////////////
    Colon,                          // : 
    Comment,                        // --
};


// Armazenar um token + lexema
const StringifiedToken = struct {
    lexeme: []const u8,
    token: ReservedToken,
};


const keywords_map = [_]struct { []const u8, ReservedToken } {
    // Fluxo
    .{ "module", .kwModule },
    .{ "package", .kwPackage },
    .{ "proc", .kwProc },
    .{ "is", .kwIs },
    .{ "end", .kwEnd },
    .{ "call", .kwCall },
    .{ "return", .kwReturn },
    .{ "if", .kwIf },
    .{ "then", .kwThen },
    .{ "loop", .kwLoop },
    .{ "exit", .kwExit },
    .{ "when", .kwWhen },
    .{ "block", .kwBlock },
    
    // Pilha (Stack)
    .{ "push", .kwPush },
    .{ "drop", .kwDrop },
    .{ "dup", .kwDup },
    .{ "swap", .kwSwap },

    // Aritmética
    .{ "add", .kwAdd },
    .{ "sub", .kwSub },
    .{ "mul", .kwMul },
    .{ "div", .kwDiv },

    // Comparação
    .{ "eq", .kwEq },
    .{ "gt", .kwGt },
    .{ "lt", .kwLt },

    // Movimento de dados 
    .{ "set", .kwSet },
    .{ "get", .kwSet },
};

// Keywords -> Token
fn match_reserved ( lexeme: []const u8 ) ReservedToken {
    for ( keywords_map ) |kw| {
        if ( mem.eql ( u8, lexeme, kw.@"0" ) ) return kw.@"1";
    }
    return .Identifier;
}

fn match_operator ( c1: u8, c2: u8 ) ReservedToken {
    if ( c1 == '-' and c2 == '-' ) return .Comment;
    if ( c1 == ':' ) return .Colon;
    return .Unknown;
}

fn parserStringWithEscape ( str: []const u8, alloc: std.mem.Allocator ) ![]u8 {
    // Verificar
    if ( str.len < 2 or str [ 0 ] != '"' or str [ str.len-1 ] != '"' ) {
        return error.InvalidStringFormat;
    }

    // Remover aspas
    const content = str[1..str.len-1];
    var result = std.ArrayList ( u8 ).init ( alloc );
    var index: usize = 0;

    while ( index < content.len ) {
        const c = content [ index ];

        if ( c == '\\' ) {
            if ( index + 1 >= content.len )
                return error.InvalidEscape;
            const escape = content[ index + 1 ];

            switch ( escape ) {
                '\\'       =>   try    result.append ( '\\' ),
                '"'        =>   try    result.append ( '"' ),
                'n'        =>   try    result.append ( '\n' ),
                '\''       =>   try    result.append ( '\'' ), 
                't'        =>   try    result.append ( '\t' ),
                'r'        =>   try    result.append ( '\r' ),
                '0'        =>   try    result.append ( 0 ),
                'x'        =>   {
                    // \xHH
                    if ( index + 3 > content.len )
                        return error.InvalidHexEscape;
                    const hex_str = content [ index+2..index+4 ];
                    const byte = std.fmt.parseInt ( u8, hex_str, 16 ) catch {
                        return error.InvalidHexEscape;
                    };
                    try result.append ( byte );
                    index += 2;
                },
                'u'        =>   {
                    // \uHHHH ( unicode )
                    if ( index + 5 > content.len )
                        return error.InvalidUnicodeEscape;
                    const hex_str = content [ index+2..index+6 ];
                    const code_point = std.fmt.parseInt ( u21, hex_str, 16 ) catch {
                        return error.InvalidUnicodeEscape;
                    };
                    
                    var buff: [ 4 ]u8 = undefined; 
                    const len = std.unicode.utf8Encode ( code_point, &buff ) catch {
                        return error.InvalidUnicode;
                    };
                    try result.appendSlice ( buff [ 0..len ] );
                    index += 4;
                },
                else       =>          return error.UnknownEscape,
            }

            index += 2;
        } else {
            try result.append ( c );
            index += 1;
        }
    }

    return result.toOwnedSlice ( );
}

fn lexer ( source: []const u8, alloc: std.mem.Allocator ) ![]StringifiedToken {
    var tokens = std.ArrayList( StringifiedToken ).init ( alloc );
    var index: usize = 0;

    while ( index < source.len ) {
        const c = source [ index ];

        // Pular espaçc 
        if ( c == ' ' or c == '\n' or c == '\t' ) {
            index += 1;
            continue;
        }

        // Comentários
        if ( c == '-' and index + 1 < source.len and source [ index + 1 ] == '-' ) {
            // avança até o fim da linha
            while ( index < source.len and source [ index ] != '\n' ) : ( index += 1 ) {}
            continue;
        }

        // Detectar ":" sozinho
        if ( c == ':' ) {
            try tokens.append( StringifiedToken { .lexeme = ":", .token =  .Colon } );
            index += 1;
            continue;
        }

        // Detectar identificador/palavra-chave
        if ( std.ascii.isAlphabetic ( c ) ) {
            const start = index;
            
            while ( index < source.len and std.ascii.isAlphanumeric ( source [ index ] )) : ( index += 1 ) {}
            
            const lexeme = source [ start..index ];
            const token = match_reserved ( lexeme );
            
            try tokens.append ( StringifiedToken {
                .lexeme = lexeme,
                .token = token,
            });

            continue;
        }

        // detectar número 
        if ( std.ascii.isDigit ( c ) ) {
            const start = index;

            while ( index < source.len and std.ascii.isDigit ( source [ index ] ) ) : ( index += 1 ) {}

            const lexeme = source [ start..index ];
            try tokens.append ( StringifiedToken {
                .lexeme = lexeme,
                .token = .NumberLiteral,
            });

            continue;
        }

        // TODO adicionar string literal futuramente
        if ( c == '"' ) {
            const start = index;
            index += 1; // Pula "
            // var escape: bool = true;

            while ( index < source.len ) {
                if ( source [ index ] == '\\') {
                    // Pula o escape e o próximo caractere
                    index += 2;
                    continue;
                }

                if ( source [ index ] == '"' ) {
                    // Fecha a string 
                    const lexeme = source [ start..index + 1 ];
                    
                    // Verificar escapes
                    _ = try parserStringWithEscape ( lexeme, alloc );

                    try tokens.append ( StringifiedToken {
                        .lexeme = lexeme,
                        .token = .StringLiteral,
                    });
                    index += 1;
                    break;
                }

                index += 1;
            }
            
            if ( index >= source.len ) {
                return error.UnclosedString;
            }

            continue;
        }

        try tokens.append ( StringifiedToken {
            .lexeme = source [ index..index + 1],
            .token = .Unknown,
        });
        index += 1;
    }

    return try tokens.toOwnedSlice ( );
}

// Nome do token para debug
fn token_name ( tok: ReservedToken ) []const u8 {
    return switch ( tok ) {
        .Unknown        =>      "Unknown",
        .Identifier     =>      "Identifier",
        .NumberLiteral  =>      "NumberLiteral",
        .StringLiteral  =>      "StringLiteral",
        
        // Fluxo 
        .kwModule       =>      "kwModule",
        .kwPackage      =>      "kwPackage",
        .kwProc         =>      "kwProc",
        .kwIs           =>      "kwIs",
        .kwEnd          =>      "kwEnd",
        .kwCall         =>      "kwCall",
        .kwReturn       =>      "kwReturn",
        .kwIf           =>      "kwIf",
        .kwThen         =>      "kwThen",
        .kwLoop         =>      "kwLoop",
        .kwExit         =>      "kwExit",
        .kwWhen         =>      "kwWhen",
        .kwBlock        =>      "kwBlock",

        // Pilha 
        .kwPush         =>      "kwPush",
        .kwDrop         =>      "kwDrop",
        .kwDup          =>      "kwDup",
        .kwSwap         =>      "kwSwap",

        // Aritmética/lógica
        .kwAdd          =>      "kwAdd",
        .kwSub          =>      "kwSub",
        .kwDiv          =>      "kwDiv",
        .kwMul          =>      "kwMul",
        .kwEq           =>      "kwEq",
        .kwGt           =>      "kwGt",
        .kwLt           =>      "kwLt",
        
        // Movimentação de dados 
        .kwSet          =>      "kwSet",
        .kwGet          =>      "kwGet",

         // Símbolos
        .Colon          =>      "Colon",
        .Comment        =>      "Comment",
    };
}

// Teste
pub fn main ( ) !void {
    const code = 
    \\package main
    \\
    \\module main
    \\
    \\proc main ( ) is
    \\      push 1  -- Adiciona 1
    \\      push 2  -- Adiciona 2
    \\      add
    \\end
    ;

    const alloc = std.heap.page_allocator;
    const tokens = try lexer(code, alloc);

    for (tokens) |t| {
        std.debug.print("Token: {s} => Lexer:{s}\n", .{ token_name( t.token ), t.lexeme } );
    }
}
