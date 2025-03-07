import UIKit

/// defines static utility functions for view controllers
class SettingsViewUtilities {
    
    /// no init necessary
    private init() {
        
    }
    
    /// for cell at cellIndex and SectionIndex, configures the cell according to viewModel. tableView is needed because if UISwitch is in the list of settings, then a reload must be done whenever the switch changes value
    static func configureSettingsCell(cell: inout SettingsTableViewCell, forRowWithIndex rowIndex: Int, forSectionWithIndex sectionIndex: Int, withViewModel viewModel: SettingsViewModelProtocol, tableView: UITableView) {
        
        // start setting textColor to black, could change to gray if setting is not enabled
        cell.textLabel?.textColor = UIColor.black
        cell.detailTextLabel?.textColor = UIColor.black
        
        // first the two textfields
        cell.textLabel?.text = viewModel.settingsRowText(index: rowIndex)
        cell.detailTextLabel?.text = viewModel.detailedText(index: rowIndex)
        
        // if not enabled, then no need to adding anything else
        if viewModel.isEnabled(index: rowIndex) {
            
            // setting enabled, get accessory type and accessory view
            cell.accessoryType = viewModel.accessoryType(index: rowIndex)
            
            switch cell.accessoryType {
            case .checkmark, .detailButton, .detailDisclosureButton, .disclosureIndicator:
                cell.selectionStyle = .gray
            case .none:
                cell.selectionStyle = .none
            @unknown default:
                cell.selectionStyle = .none
            }
            
            cell.accessoryView = viewModel.uiView(index: rowIndex)
            
            // if uiview is an uiswitch then a reload must be initiated whenever the switch changes, either complete view or just the section
            if let view = cell.accessoryView as? UISwitch {
                view.addTarget(self, action: {
                    (theSwitch:UISwitch) in
                    
                    checkIfReloadNeededAndReloadIfNeeded(tableView: tableView, viewModel: viewModel, rowIndex: rowIndex, sectionIndex: sectionIndex)
                    
                }, for: UIControl.Event.valueChanged)
            }
            
        } else {
            
            // setting not enabled, set color to grey, no accessory type to be added
            cell.textLabel?.textColor = UIColor.gray
            cell.detailTextLabel?.textColor = UIColor.gray
            
            // set accessory and selectionStyle to none, because no action is required when user clicks the row
            cell.accessoryType = .none
            cell.selectionStyle = .none
            
            // set accessoryView to nil
            cell.accessoryView = nil
            
        }

    }
    
    /// for cell at cellIndex and SectionIndex, runs the selectedRowAction. tableView is needed because a reload must be done in some cases
    static func runSelectedRowAction(selectedRowAction: SettingsSelectedRowAction, forRowWithIndex rowIndex: Int, forSectionWithIndex sectionIndex: Int, withViewModel viewModel: SettingsViewModelProtocol, tableView: UITableView, forUIViewController uIViewController: UIViewController) {
        
            
            switch selectedRowAction {
                
            case let .askText(title, message, keyboardType, text, placeHolder, actionTitle, cancelTitle, actionHandler, cancelHandler):
                
                let alert = UIAlertController(title: title, message: message, keyboardType: keyboardType, text: text, placeHolder: placeHolder, actionTitle: actionTitle, cancelTitle: cancelTitle, actionHandler: { (text:String) in
                    
                    // do the action
                    actionHandler(text)
                    
                    // check if refresh is needed, either complete settingsview or individual section
                    self.checkIfReloadNeededAndReloadIfNeeded(tableView: tableView, viewModel: viewModel, rowIndex: rowIndex, sectionIndex: sectionIndex)
                    
                }, cancelHandler: cancelHandler)
                
                // present the alert
                uIViewController.present(alert, animated: true, completion: nil)
                
            case .nothing:
                break
                
            case let .callFunction(function):
                
                // call function
                function()
                
                // check if refresh is needed, either complete settingsview or individual section
                self.checkIfReloadNeededAndReloadIfNeeded(tableView: tableView, viewModel: viewModel, rowIndex: rowIndex, sectionIndex: sectionIndex)
                
            case let .selectFromList(title, data, selectedRow, actionTitle, cancelTitle, actionHandler, cancelHandler, didSelectRowHandler):
                
                // configure pickerViewData
                let pickerViewData = PickerViewData(withMainTitle: nil, withSubTitle: title, withData: data, selectedRow: selectedRow, withPriority: nil, actionButtonText: actionTitle, cancelButtonText: cancelTitle, onActionClick: {(_ index: Int) in
                    actionHandler(index)
                    
                    // check if refresh is needed, either complete settingsview or individual section
                    self.checkIfReloadNeededAndReloadIfNeeded(tableView: tableView, viewModel: viewModel, rowIndex: rowIndex, sectionIndex: sectionIndex)
                    
                }, onCancelClick: {
                    if let cancelHandler = cancelHandler { cancelHandler() }
                }, didSelectRowHandler: {(_ index: Int) in
                    
                    if let didSelectRowHandler = didSelectRowHandler {
                        didSelectRowHandler(index)
                    }
                    
                })
                
                // create and present pickerviewcontroller
                PickerViewController.displayPickerViewController(pickerViewData: pickerViewData, parentController: uIViewController)
                
                break
                
            case .performSegue(let withIdentifier):
                uIViewController.performSegue(withIdentifier: withIdentifier, sender: nil)
                
            case let .showInfoText(title, message):
                
                UIAlertController(title: title, message: message, actionHandler: nil).presentInOwnWindow(animated: true, completion: nil)
                
            }
            

    }

    // MARK: private helper functions
    
    /// for specified UITableView, viewModel, rowIndex and sectionIndex, check if a refresh of just the section is needed or the complete settings view, and refresh if so
    ///
    /// Changing one setting value, may need hiding or masking or other setting rows. Goal is to minimize the refresh to the section if possible and to avoid refreshing the whole screen as much as possible.
    /// This function will verify if complete reload is needed or not
    private static func checkIfReloadNeededAndReloadIfNeeded(tableView: UITableView, viewModel:SettingsViewModelProtocol, rowIndex:Int, sectionIndex:Int ) {
        
        if viewModel.completeSettingsViewRefreshNeeded(index: rowIndex) {
            tableView.reloadSections(IndexSet(integersIn: 0..<tableView.numberOfSections), with: .none)
        } else {
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
        }
    }
    


}
