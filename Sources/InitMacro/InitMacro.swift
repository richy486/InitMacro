/// Generates a public initializer.
///
/// Example:
///
///   @Init(wildcards: [], public: true)
///   public final class Test {
///       let age: Int
///       let cash: Double?
///       let name: String
///   }
///
/// produces
///
///    public final class Test {
///        let age: Int
///        let cash: Double?
///        let name: String
///
///        public init(
///            age: Int,
///            cash: Double?,
///            name: String
///        ) {
///            self.age = age
///            self.cash = cash
///            self.name = name
///        }
///    }
///
/// - Parameters:
///   - customDefaultName: Should an init with the `customDefaultName` be generated.
///   - initTitle: Title for the init comments.
///   - customDefaultInitTitle: Title for the custom default init comments.
///   - wildcards: Array containing the specified properties that should be wildcards.
///   - public: The flag to indicate if the init is public or not.
@attached(member, names: named(init))
public macro Init(
  customDefaultName: String? = nil,
  initTitle: String? = nil,
  customDefaultInitTitle: String? = nil,
  wildcards: [String] = [],
  public: Bool = true
) = #externalMacro(
  module: "InitMacroImplementation",
  type: "InitMacro"
)

@attached(peer, names: prefixed(description_))
public macro Description(text: String) = #externalMacro(module: "InitMacroImplementation", type: "DescriptionMacro")
