import UIKit

/// functions that define the contents of a Section
///
/// The protocol defines the Section title, the text and detailedText to be shown in a cell of that secion, the accessoryType (none, disclosure, detail button, detail disclosure button), the UIView to be shown if applicable (eg UISwitch), the nomber of rows in the Section, and last but not least is it enabled or not
///
/// in case isEnabled returns false, then the didSelectRow action will never be applied
protocol SettingsViewModelProtocol {
    
    /// what title should be shown in a section
    /// - returns:
    /// the section title, optional, for section
    func sectionTitle() -> String?
    
    /// the text to be shown for a specific row in the Section
    /// - returns:
    ///     the text
    func settingsRowText(index:Int) -> String
    
    /// the accessoryType to be shown for a specific row in the Section (none, disclosure, detail button, detail disclosure button)
    /// - returns:
    ///     the accessoryType
    func accessoryType(index:Int) -> UITableViewCell.AccessoryType
    
    /// the detailedText to be shown for a specific row in the Section
    /// - returns:
    ///     the detailedText corresponding to cel on index
    func detailedText(index:Int) -> String?
    
    /// used for adding a a view in a settings cell, for the moment only used for UISwitch (on/off) - maybe can also be used to add a button with an image ? eg + sign for alert entries
    /// - returns:
    ///     a UIView, nil if no UIView to be shown (example see SettingsViewHealthKitSettingsViewModel)
    func uiView(index:Int) -> UIView?
    
    /// what's the number of rows in the section
    /// - returns:
    ///     number of rows in the section
    func numberOfRows() -> Int
    
    /// what should happen if a row is selected
    /// - parameters:
    ///     - index: index of selected row in the Section
    /// - returns:
    ///     a selectedRowAction
    func onRowSelect(index:Int) -> SettingsSelectedRowAction
    
    /// is the setting enabled or not
    ///
    /// if not enabled, then clicking the setting should not have any reaction, also it should be made clear in UI that setting is not enabled (ey gray color)
    func isEnabled(index:Int) -> Bool
    
    /// does a change of the setting need a refresh of the complete settings screen yes or no
    ///
    /// example switching from master to follower in the general settings, requires changing the UI for NightScout settings - in this case a complete refresh of all settings is needed
    ///
    /// Goal is to minimize the refresh to the section if possible and to avoid refreshing the whole screen as much as possible.
    /// This function will verify if complete reload is needed or not
    func completeSettingsViewRefreshNeeded(index:Int) -> Bool
    
}

protocol SettingsProtocol {
    
    /// returns a SettingsViewModelProtocol
    func viewModel() -> SettingsViewModelProtocol
    
}
