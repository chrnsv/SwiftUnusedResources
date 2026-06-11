import SwiftSyntax

/// Resolution of R.swift-style access (`R.image.star`) and Xcode-generated asset symbols
/// (`UIImage.star`, `Image(.star)`, `UIImage(resource: .star)`) reached through a
/// `DeclReferenceExprSyntax`. Kept separate from the visit overrides.
extension SourceVisitor {
    func findR(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard node.baseName.text == "R" else {
            return nil
        }

        let members = members(in: node).dropFirst()

        guard members.first == kind.rawValue, let name = members.dropFirst().first else {
            return nil
        }

        return .rswift(name, kind)
    }

    func findGeneratedAsset(
        in node: DeclReferenceExprSyntax,
        with kind: ExploreKind
    ) -> ExploreUsage? {
        guard Self.generatedClassKinds[node.baseName.text] == kind else {
            return nil
        }

        if let call = initializerCall(of: node) {
            // collectValue resolves ternary / if / switch branches before recording, so
            // `UIImage(resource: flag ? .a : .b)` records both assets. Usages are appended
            // directly; a DeclRef has no children worth skipping, so returning nil is fine.
            if call.arguments.count == 1, let argument = call.arguments.first {
                collectValue(argument.expression, with: kind)
            }

            return nil
        }
        else {
            var members = members(in: node).array()

            if let first = members.first, Self.assetModules.contains(first) {
                members.removeFirst()
            }

            // `members.first == baseName` rejects chains rooted in an unknown namespace:
            // in `MyKit.Image.star` the first member is `MyKit`, so `Image` there is some
            // custom type, not the SwiftUI one.
            guard members.count >= 2, members.first == node.baseName.text else {
                return nil
            }

            let name = members[1]

            // Asset symbols can never be named `init`; `UIImage.init(named:)` is not an asset.
            guard name != "init" else {
                return nil
            }

            return .generated(name, kind)
        }
    }

    /// The call node when `node` is the called type of an initializer call — either plain
    /// `UIImage(...)` or module-qualified `SwiftUI.Image(...)`.
    private func initializerCall(of node: DeclReferenceExprSyntax) -> FunctionCallExprSyntax? {
        if let call = node.parent?.as(FunctionCallExprSyntax.self) {
            return call
        }

        guard
            let member = node.parent?.as(MemberAccessExprSyntax.self),
            member.declName.id == node.id,
            let base = member.base?.as(DeclReferenceExprSyntax.self),
            Self.assetModules.contains(base.baseName.text)
        else {
            return nil
        }

        return member.parent?.as(FunctionCallExprSyntax.self)
    }

    private func members(in node: DeclReferenceExprSyntax) -> some RandomAccessCollection<String> {
        guard let parent = node.parent?.as(MemberAccessExprSyntax.self) else {
            return []
        }

        let usage = sequence(first: parent) { $0.parent?.as(MemberAccessExprSyntax.self) }
            .array()
            .last

        guard let usage else {
            return []
        }

        let visitor = MemberVisitor(viewMode: viewMode)

        visitor.walk(usage)

        return visitor.members
    }
}
