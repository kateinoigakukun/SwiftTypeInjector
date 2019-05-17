import SwiftSyntax
import TypeCheckedAST

final class ClosureExprRewriter {
    func write(_ syntax: ClosureExprSyntax, node: ASTNode) -> ClosureExprSyntax {
        if let input = syntax.signature?.input as? ParameterClauseSyntax {
            return write(syntax, input: input, node: node)
        }
        if let parameterList = syntax.signature?.input as? ClosureParamListSyntax {
            return write(syntax, parameterList: parameterList, node: node)
        }
        return syntax
    }

    // map { i in }
    func write(_ syntax: ClosureExprSyntax, parameterList: ClosureParamListSyntax, node: ASTNode) -> ClosureExprSyntax {
        guard let parenNode = node.find(point: Point(position: syntax.position)),
            let closureNode = parenNode.find(where: { $0.name == "function_conversion_expr" })
                ?? parenNode.find(where: { $0.name == "closure_expr" }),
            let closureRawType = closureNode.type,
            let closureType = try? parseFunctionType(closureRawType) else {
                return syntax
        }

        let typedParameterList: [FunctionParameterSyntax] = zip(parameterList, closureType.input).enumerated()
            .map { (element)-> FunctionParameterSyntax in
                let (index, (parameter, type)) = element
                let newType: FunctionParameterSyntax = self.addTypeAnnotation(
                    to: parameter, type: type
                )
                let isLast: Bool = index == parameterList.count-1
                if isLast {
                    return newType
                } else {
                    return newType.withTrailingComma(SyntaxFactory.makeCommaToken(trailingTrivia: .spaces(1)))
                }
        }
        let newParameterList: FunctionParameterListSyntax = SyntaxFactory.makeFunctionParameterList(typedParameterList)
        let parameterClause: ParameterClauseSyntax = SyntaxFactory.makeParameterClause(
            leftParen: SyntaxFactory.makeLeftParenToken(),
            parameterList: newParameterList,
            rightParen: SyntaxFactory.makeRightParenToken()
        )
        var newSignature: ClosureSignatureSyntax? = syntax.signature?.withInput(parameterClause)

        if let _ = syntax.signature?.output {
            return syntax.withSignature(newSignature)
        }
        let output: ReturnClauseSyntax = SyntaxFactory.makeReturnClause(
            arrow: SyntaxFactory.makeArrowToken(leadingTrivia: .spaces(1)),
            returnType: SyntaxFactory.makeTypeIdentifier(
                closureType.output.description,
                leadingTrivia: .spaces(1),
                trailingTrivia: .spaces(1)
            )
        )

        newSignature = newSignature?.withOutput(output)
        return syntax.withSignature(newSignature)
    }

    func addTypeAnnotation(to parameter: ClosureParamSyntax, type: Type) -> FunctionParameterSyntax {
        let funcParameter: FunctionParameterSyntax = SyntaxFactory.makeFunctionParameter(
            attributes: nil, firstName: parameter.name.withoutTrailingTrivia(), secondName: nil,
            colon: nil,
            type: nil,
            ellipsis: nil, defaultArgument: nil, trailingComma: nil
        )
        guard parameter.name.text != "_" else { return funcParameter }

        return funcParameter
            .withColon(SyntaxFactory.makeColonToken(trailingTrivia: .spaces(1)))
            .withType(SyntaxFactory.makeTypeIdentifier(type.description))
    }


    // map { (i) in }
    func write(_ syntax: ClosureExprSyntax, input: ParameterClauseSyntax, node: ASTNode) -> ClosureExprSyntax {
        guard let parenNode = node.find(point: Point(position: syntax.position)),
            let closureNode = parenNode.find(where: { $0.name == "closure_expr" }),
            let closureRawType = closureNode.type,
            let closureType = try? parseFunctionType(closureRawType) else {
                return syntax
        }

        guard let parameterListNode = node.find(point: Point(position: input.parameterList.position)),
            parameterListNode.name == "parameter_list" else {
                return syntax
        }

        let typedParameterList: [FunctionParameterSyntax] = zip(input.parameterList, closureType.input).map {
            self.addTypeAnnotation(to: $0, type: $1)
        }
        let newParameterList: FunctionParameterListSyntax = typedParameterList.enumerated()
            .reduce(input.parameterList) { (parameterList: FunctionParameterListSyntax, element: (offset: Int, element: FunctionParameterSyntax)) -> FunctionParameterListSyntax in
                let (index, parameter) = element
                return parameterList.replacing(childAt: index, with: parameter)
        }
        let newInput: ParameterClauseSyntax = input.withParameterList(newParameterList)

        if let _ = syntax.signature?.output {
            let newSignature: ClosureSignatureSyntax? = syntax.signature?.withInput(newInput)
            return syntax.withSignature(newSignature)
        }
        let output: ReturnClauseSyntax = SyntaxFactory.makeReturnClause(
            arrow: SyntaxFactory.makeArrowToken(),
            returnType: SyntaxFactory.makeTypeIdentifier(
                closureType.output.description,
                leadingTrivia: .spaces(1),
                trailingTrivia: .spaces(1)
            )
        )
        let newSignature: ClosureSignatureSyntax? = syntax.signature?.withInput(newInput).withOutput(output)
        return syntax.withSignature(newSignature)
    }

    func addTypeAnnotation(to parameter: FunctionParameterSyntax, type: Type) -> FunctionParameterSyntax {
        guard parameter.firstName?.text != "_" else { return parameter }
        let colon: TokenSyntax = SyntaxFactory.makeColonToken().withTrailingTrivia(.spaces(1))
        let type: TypeSyntax = SyntaxFactory.makeTypeIdentifier(type.description)
        return parameter.withColon(colon).withType(type)
    }
}
