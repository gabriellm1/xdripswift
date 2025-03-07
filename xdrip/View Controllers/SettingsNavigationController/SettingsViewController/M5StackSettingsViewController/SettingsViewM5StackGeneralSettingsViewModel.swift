import UIKit

fileprivate enum Setting:Int, CaseIterable {
    
    //blood glucose  unit
    case textColor
    
}

struct SettingsViewM5StackGeneralSettingsViewModel: SettingsViewModelProtocol {
    
    func sectionTitle() -> String? {
        return Texts_SettingsView.sectionTitleGeneral
    }
    
    func settingsRowText(index: Int) -> String {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        
        switch setting {
        case .textColor:
            return Texts_M5Stack_SettingsView.textColor
        }

    }
    
    func accessoryType(index: Int) -> UITableViewCell.AccessoryType {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        
        switch setting {
        case .textColor:
            return UITableViewCell.AccessoryType.disclosureIndicator
        }
    }
    
    func detailedText(index: Int) -> String? {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        
        switch setting {
        case .textColor:
            var textColor = UserDefaults.standard.m5StackTextColor
            if textColor == nil {
                textColor = ConstantsM5Stack.defaultTextColor
            }
            return textColor?.description
        }
    }
    
    func uiView(index: Int) -> UIView? {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        
        switch setting {
        case .textColor:
            return nil
        }
    }
    
    func numberOfRows() -> Int {
        return Setting.allCases.count
    }
    
    func onRowSelect(index: Int) -> SettingsSelectedRowAction {
        guard let setting = Setting(rawValue: index) else { fatalError("Unexpected Section") }
        
        switch setting {
        case .textColor:
            var texts = [String]()
            var colors = [M5StackTextColor]()
            for textColor in M5StackTextColor.allCases {
                texts.append(textColor.description)
                colors.append(textColor)
            }
            
            //find index for text color currently stored in userdefaults
            var selectedRow:Int?
            if let textColor = UserDefaults.standard.m5StackTextColor?.description {
                selectedRow = texts.firstIndex(of:textColor)
            }
            
            return SettingsSelectedRowAction.selectFromList(title: Texts_M5Stack_SettingsView.textColor, data: texts, selectedRow: selectedRow, actionTitle: nil, cancelTitle: nil, actionHandler: {(index:Int) in
                if index != selectedRow {
                    UserDefaults.standard.m5StackTextColor = colors[index]
                }
            }, cancelHandler: nil, didSelectRowHandler: nil)

        }
    }
    
    func isEnabled(index: Int) -> Bool {
        return true
    }
    
    func completeSettingsViewRefreshNeeded(index: Int) -> Bool {
        return false
    }
    
    
}
