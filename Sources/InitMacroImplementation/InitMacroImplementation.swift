import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

public struct DescriptionMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    return []
  }
}

/// Generates a public initializer.
///
/// Example:
///
/// @Init(customDefaultName: "original", wildcards: [], public: true)
/// public final class Test {
///   let age: Int
///   let cash: Double?
///   let name: String
/// }
///
/// produces
///
/// public final class Test {
///   let age: Int
///   let cash: Double?
///   let name: String
///
///   public init(
///     age: Int,
///     cash: Double?,
///     name: String
///   ) {
///     self.age = age
///     self.cash = cash
///     self.name = name
///   }
///
///   public init(
///     _ original: Self,
///     age: Int? = nil,
///     cash: Double? = nil,
///     name: String? = nil
///   ) {
///     self.age = age ?? original.age
///     self.cash = cash ?? original.cash
///     self.name = name ?? original.name
///   }
/// }
///
/// - Parameters:
///   - customDefaultName: Should an init with the `customDefaultName` be generated.
///   - wildcards: Array containing the specified properties that should be wildcards.
///   - public: The flag to indicate if the init is public or not.
struct InitMacro: MemberMacro {
  static func expansion(
    of attribute: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    // Only `struct` and `class` is suitable for this macro
    guard declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self) else {
      let message: DiagnosticMessage
      if !declaration.is(StructDeclSyntax.self) {
        message = InitMacroDiagnostic.notAsStruct("InitMacro")
      } else {
        message = InitMacroDiagnostic.notAsClass("InitMacro")
      }
      let error = Diagnostic(
        node: attribute._syntaxNode,
        message: message
      )
      context.diagnose(error)
      return []
    }
    
    var accessorType = false
    var customDefaultName: String? = nil
    var wildcards = [String]()
    let members: MemberBlockItemListSyntax
    let typeName: String
    var initTitle: String? = nil
    var customDefaultInitTitle: String? = nil
    
    if let decl = declaration.as(ClassDeclSyntax.self) {
      (accessorType, wildcards, customDefaultName, initTitle, customDefaultInitTitle) = prefixAndAttributes(
        accessorPrefix: getModifiers("", decl.modifiers),
        attributes: decl.attributes
      )
      members = decl.memberBlock.members
      typeName = decl.identifier.text
    } else if let decl = declaration.as(StructDeclSyntax.self) {
      (accessorType, wildcards, customDefaultName, initTitle, customDefaultInitTitle) = prefixAndAttributes(
        accessorPrefix: getModifiers("", decl.modifiers),
        attributes: decl.attributes
      )
      members = decl.memberBlock.members
      typeName = decl.identifier.text
    } else {
      return []
    }
    
    var expansionArray: [DeclSyntax] = []
    let initDeclSyntax = try declarationSyntax(
      members: members,
      wildcards: wildcards,
      accessorType: accessorType,
      typeName: typeName,
      initTitle: initTitle
    )
    expansionArray.append("\(raw: initDeclSyntax)")
    
    if let customDefaultName {
      let initCustomDefaultNameDeclSyntax = try declarationSyntax(
        members: members,
        wildcards: wildcards,
        accessorType: accessorType,
        typeName: typeName,
        initTitle: customDefaultInitTitle ?? initTitle,
        customDefaultName: customDefaultName
      )
      expansionArray.append("\(raw: initCustomDefaultNameDeclSyntax)")
    }
    
    return expansionArray
  }
  
  private static func prefixAndAttributes(accessorPrefix: String, attributes: AttributeListSyntax?) -> (
    accessorType: Bool,
    wildcards: [String],
    customDefaultName: String?,
    initTitle: String?,
    customDefaultInitTitle: String?
  ) {
    var wildcards = [String]()
    
    // Get attributes for Init macro
    let attributes = getAttributes(attributes, "Init")?.arguments?.as(LabeledExprListSyntax.self)
    
    // Analyse the `customDefaultName` parameter
    let customDefaultName: String?
    if let customDefaultNameAttributes = attributes?
      .first(where: { "\($0)".contains("customDefaultName") })?
      .expression.as(StringLiteralExprSyntax.self)?
      .segments.first?.as(StringSegmentSyntax.self) {
      customDefaultName = "\(customDefaultNameAttributes)"
    } else {
      customDefaultName = nil
    }
    
    // initTitle
    let initTitle: String?
    if let initTitleAttributes = attributes?
      .first(where: { "\($0)".contains("initTitle") })?
      .expression.as(StringLiteralExprSyntax.self)?
      .segments.first?.as(StringSegmentSyntax.self) {
      initTitle = "\(initTitleAttributes)"
    } else {
      initTitle = nil
    }

    // customDefaultInitTitle
    let customDefaultInitTitle: String?
    if let customDefaultInitTitleAttributes = attributes?
      .first(where: { "\($0)".contains("customDefaultInitTitle") })?
      .expression.as(StringLiteralExprSyntax.self)?
      .segments.first?.as(StringSegmentSyntax.self) {
      customDefaultInitTitle = "\(customDefaultInitTitleAttributes)"
    } else {
      customDefaultInitTitle = nil
    }
    
    // Analyse the `wildcards` parameter
    if let wildcardsAttributes = attributes?
      .first(where: { "\($0)".contains("wildcards") })?
      .expression.as(ArrayExprSyntax.self)?
      .elements {
      for attribute in wildcardsAttributes {
        if let key = attribute.expression.as(StringLiteralExprSyntax.self)?
          .segments.first?.as(StringSegmentSyntax.self)?
          .content {
          wildcards.append("\(key)")
        }
      }
    }
    
    // Analyse the `public` parameter
    var accessorType = accessorPrefix.contains("public")
    if let publicAttribute = attributes?
      .first(where: { "\($0)".contains("public") })?
      .expression.as(BooleanLiteralExprSyntax.self)?.literal {
      accessorType = "\(publicAttribute)" == "true"
    }
    
    return (accessorType, wildcards, customDefaultName, initTitle, customDefaultInitTitle)
  }
  
  private static func declarationSyntax(
    members: MemberBlockItemListSyntax,
    wildcards: [String],
    accessorType: Bool,
    typeName: String,
    initTitle: String?,
    customDefaultName: String? = nil
  ) throws -> InitializerDeclSyntax {
    var comments = String()
    var parameters = [String]()
    var assignments = [String]()
    
    (comments, parameters, assignments) = makeData(
      wildcards: wildcards,
      members: members,
      typeName: typeName,
      initTitle: initTitle,
      customDefaultName: customDefaultName
    )
    
    let initBody: [CodeBlockItemListSyntax.Element] = assignments.enumerated().map { index, assignment in
      if index == 0 {
        return "\(raw: assignment)"
      } else {
        return "\n\(raw: assignment)"
      }
    }
    
    let initDeclSyntax = try InitializerDeclSyntax(
      SyntaxNodeString(
        stringLiteral: "\(comments)\(accessorType ? "public " : "")init(\n\(parameters.joined(separator: ",\n"))\n)"
      ),
      bodyBuilder: { .init(initBody) }
    )
    
    return initDeclSyntax
  }
  
  private static func makeData(
    wildcards: [String],
    members: MemberBlockItemListSyntax,
    typeName: String,
    initTitle: String?,
    customDefaultName: String?
  ) -> (String, [String], [String]) {
    
    var parameters = [String]()
    var assignments = [String]()
    
    let title = initTitle ?? "Initializes a `\(typeName)`."
    var comments: String =
      """
      /// \(title)
      ///
      /// - Parameters:
      
      """
    
    if let customDefaultName {
      parameters.append("_ \(customDefaultName): Self")
    }

    for member in members {
      if let syntax = member.decl.as(VariableDeclSyntax.self),
         case let bindings = syntax.bindings,
         let pattern = bindings.first,
         let identifier = pattern.pattern.as(IdentifierPatternSyntax.self)?.identifier,
         let type = pattern.typeAnnotation?.type,
         !(syntax.bindingSpecifier.tokenKind == .keyword(.let) && pattern.initializer != nil)
      {
        let comment: String
        let attributeComments: [String] = syntax.attributes.compactMap { attribute /*-> String?*/ in
          guard let attributeSyntax = attribute.as(AttributeSyntax.self) else { return nil }
          
          guard attributeSyntax.attributeName.description == "Description" else { return nil }
          

          let textArgument = attributeSyntax.arguments?.as(LabeledExprListSyntax.self)?.first?.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text
          
          return textArgument
        }
        
        if let first = attributeComments.first {
          comment = "///   - \(identifier): \(first)"
        } else {
          comment = "///   - \(identifier): TODO: add comment"
        }
        
        
        comments.append(comment + "\n")
                
        guard let type = pattern.typeAnnotation?.type else {
          fatalError()
        }
            
        let shouldUnderscoreParameter = wildcards.contains("\(identifier)")
        let identifierPrefix = "\(shouldUnderscoreParameter ? "_ " : "")"
        
        let shouldAddScaping = type.is(FunctionTypeSyntax.self)
        let typePrefix = "\(shouldAddScaping ? "@escaping " : "")"
        
        var parameter = "\(identifierPrefix)\(identifier): \(typePrefix)\(type)"
        
        if let customDefaultName {
          parameter += "? = nil"
        } else if let initializer = pattern.initializer {
          parameter += "\(initializer)"
        }
        
        let memberAccessor = getModifiers("", syntax.modifiers)
        let memberAccessorPrefix = (memberAccessor.contains("static") ? "S" : "s") + "elf"
        
        let isComputedProperty = CodeBlockSyntax(pattern.accessorBlock) != nil
        let isUsingAccessors = pattern.accessorBlock != nil
        if !isComputedProperty, !isUsingAccessors {
          parameters.append(parameter)
          if let customDefaultName {
            assignments.append("\(memberAccessorPrefix).\(identifier) = \(identifier) ?? \(customDefaultName).\(identifier)")
          } else {
            assignments.append("\(memberAccessorPrefix).\(identifier) = \(identifier)")
          }
        }
      }
    }
    
    return (comments, parameters, assignments)
  }
}

extension String {
  func containsPattern(_ pattern: String = "Optional\\((.*)\\)") -> Bool {
    extractPattern(pattern) != nil
  }
  
  func removePattern(_ pattern: String = "Optional\\((.*)\\)") -> String {
    if let match = extractPattern(pattern) {
      if let range = Range(match.range(at: 1), in: self) {
        return String(self[range])
      }
    }
    return self
  }
  
  private func extractPattern(_ pattern: String = "Optional\\((.*)\\)") -> NSTextCheckingResult? {
    do {
      let regex = try NSRegularExpression(
        pattern: pattern
      )
      return regex.firstMatch(
        in: self,
        options: [],
        range: NSRange(location: 0, length: utf16.count)
      )
    } catch { }
    return nil
  }
}

private extension AttachedMacro {
  static func getAttributes(
    _ attributes: AttributeListSyntax?,
    _ key: String
  ) -> AttributeSyntax? {
    attributes?
      .first(where: { "\($0)".contains(key) })?
      .as(AttributeSyntax.self)
  }
  
  static func getModifiers(
    _ initialModifiers: String,
    _ modifiers: DeclModifierListSyntax?
  ) -> String {
    var initialModifiers = initialModifiers
    modifiers?.forEach {
      let accessorType = $0.name
      initialModifiers += "\(accessorType.text) "
    }
    return initialModifiers
  }
}
