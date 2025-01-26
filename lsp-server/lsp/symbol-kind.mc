lang LSPSymbolKind
  -- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
  syn SymbolKind =
  | SymbolFile
  | SymbolModule
  | SymbolNamespace
  | SymbolPackage
  | SymbolClass
  | SymbolMethod
  | SymbolProperty
  | SymbolField
  | SymbolConstructor
  | SymbolEnum
  | SymbolInterface
  | SymbolFunction
  | SymbolVariable
  | SymbolConstant
  | SymbolString
  | SymbolNumber
  | SymbolBoolean
  | SymbolArray
  | SymbolObject
  | SymbolKey
  | SymbolNull
  | SymbolEnumMember
  | SymbolStruct
  | SymbolEvent
  | SymbolOperator
  | SymbolTypeParameter

  sem getSymbolKind: SymbolKind -> Int
  sem getSymbolKind =
  | SymbolFile () -> 1
  | SymbolModule () -> 2
  | SymbolNamespace () -> 3
  | SymbolPackage () -> 4
  | SymbolClass () -> 5
  | SymbolMethod () -> 6
  | SymbolProperty () -> 7
  | SymbolField () -> 8
  | SymbolConstructor () -> 9
  | SymbolEnum () -> 10
  | SymbolInterface () -> 11
  | SymbolFunction () -> 12
  | SymbolVariable () -> 13
  | SymbolConstant () -> 14
  | SymbolString () -> 15
  | SymbolNumber () -> 16
  | SymbolBoolean () -> 17
  | SymbolArray () -> 18
  | SymbolObject () -> 19
  | SymbolKey () -> 20
  | SymbolNull () -> 21
  | SymbolEnumMember () -> 22
  | SymbolStruct () -> 23
  | SymbolEvent () -> 24
  | SymbolOperator () -> 25
  | SymbolTypeParameter () -> 26
end