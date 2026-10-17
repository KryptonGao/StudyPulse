import SwiftUI





extension MistakePattern {
    var displayName: String {
        let localized = titleKey.localized()
        if localized != titleKey { return localized }
        switch self {
        case .conditionOmission: return "条件遗漏"
        case .conceptConfusion: return "概念混淆"
        case .formulaMisuse: return "公式误用"
        case .calculationError: return "计算失误"
        case .unitError: return "单位错误"
        case .incompleteReading: return "审题不完整"
        case .logicJump: return "逻辑跳步"
        case .boundaryOmission: return "边界情况遗漏"
        case .memoryError: return "记忆错误"
        case .unclearExpression: return "表达不清"
        case .methodSelection: return "方法选择错误"
        case .other: return "其他"
        }
    }

    var explanation: String {
        let localized = descriptionKey.localized()
        if localized != descriptionKey { return localized }
        switch self {
        case .conditionOmission: return "你在解题时容易提前开始推导，遗漏题目中的限制条件。"
        case .conceptConfusion: return "相近概念或定义在不同题型中被混用了。"
        case .formulaMisuse: return "公式本身记得，但适用条件或使用方式出现了偏差。"
        case .calculationError: return "思路基本正确，错误主要发生在运算或符号处理。"
        case .unitError: return "数值处理正确，但单位或量纲转换没有保持一致。"
        case .incompleteReading: return "题目还没有读完整，就已经开始作答。"
        case .logicJump: return "关键中间步骤没有写出或没有验证。"
        case .boundaryOmission: return "一般情况能处理，但边界或特殊情况容易遗漏。"
        case .memoryError: return "需要调用的定义、结论或事实没有被准确回忆。"
        case .unclearExpression: return "答案表达不够清楚，导致条件、结论或符号含义不明确。"
        case .methodSelection: return "题目识别正确，但选择的解题路径并不适合当前问题。"
        case .other: return "这类错误还需要更多信息才能进一步归纳。"
        }
    }
}
