/*
** Class:  TriggerUtils
** Created by David House 5/25/13
** Description: This class implements the logic for handling Project triggers.
*/
public with sharing class TriggerUtils {

    public static BusinessDays busDays;
    public static Boolean firstInvocation = true;

    // Project Status - Template:Recipient Map
    // Project Project status -> (email template, recipient 1, recipient 2, ...)
    private Map <String, List<String>> statusTemplateRecipientMap 
        = new Map <String, List<String>> 
            {
                'Received Ad(s)'            
                    =>new List<String> {'A', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'EmailType2@Project.com','Detail/Other','Overview'},
                'Rejected Provisioning Form'
                    =>new List<String> {'J', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'Detail/Other'},
                'Provisioned'               
                    =>new List<String> {'B::Status2::E::Status1', 'EmailType1@Project.com', 'EmailType2@Project.com'},
                'QA Sign Off'               
                    =>new List<String> {'D::Status2::F::Status1', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'EmailType2@Project.com', 'Detail/Other'},
                'Received SPSS and Step4 Specification'
                    =>new List<String> {'G', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'Detail/Other', '{Opportunity.Client_DP_QA_Email__c}'},
                'Rejected SPSS and/or Step4 Spec'
                    =>new List<String> {'K', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'Detail/Other', '{Opportunity.Client_DP_QA_Email__c}'}, 
                'Step4 Processed'
                    =>new List<String> {'H', 'EmailType1@Project.com', 'EmailType2@Project.com'},
                'QA Sign off on Step4'
                    =>new List<String> {'I', 'EmailType1@Project.com', '{Opportunity.Client_Project_Email__c}', 'EmailType2@Project.com', 'Detail/Other', 'Overview'},
                'Step4 Delivered'
                    =>new List<String> {'M', '{Opportunity.Client_Project_Email__c}', 'Detail/Other', 'Overview'},
                'QA Rejected Provisioning'
                    =>new List<String> {'N', 'EmailType1@Project.com', 'EmailType2@Project.com'},
                'QA Rejected Step4'
                    =>new List<String> {'O', 'EmailType1@Project.com', 'EmailType2@Project.com'}
                    
            };

    private Set <String> detailOtherSet = new Set <String> {'Detail','Other'};
    
    // This maps the 2 Project email addresses to the custom settings
    // This allows for changing these from Salesforce.com without recompiling this Apex class
    //  emailSettings.EmailType1__c EmailType1@Project.com
    //  emailSettings.EmailType2__c      EmailType2@Project.com
    private Map <String, String> ProjectEmailAddresses = new Map <String, String> ();

    private Map <String, String> codeQueryMap = 
        new Map <String, String> {
            'A'=>'A_%Step1',
            'G'=>'G_%Step2',
            'H'=>'H_%Step3',
            'I'=>'I_%Step4',
            'J'=>'J_%Step5',
            'K'=>'K_%Step6',
            'M'=>'M_%Step7',
            'N'=>'N_%Step8',
            'O'=>'O_%Step9'
        };
        
    public TriggerUtils () {
                
        BusinessHours bh = [Select Id From BusinessHours Where IsDefault=true];
        if (busDays == null) {
            busDays = new BusinessDays();
        }
        
        // Get custom settings
        Status_Emails__c emailSettings = Status_Emails__c.getValues('ProjectProject');
        ProjectEmailAddresses.put('EmailType1@Project.com', emailSettings.EmailType1__c);
        ProjectEmailAddresses.put('EmailType2@Project.com', emailSettings.EmailType2__c);
    }
    

    public void updateStep4FilesReceivedPlus48 (List <Project_Projects__c> newProjs) {

        System.debug('===========>>> updateStep4FilesReceivedPlus48, size: '+newProjs.size());
        
        for (Project_Projects__c nextProj : newProjs) {
            System.debug('===========>>> nextProj: '+nextProj.Id+', Step4 Files: '+nextProj.Step4_Files_Received__c);
            if (nextProj.Step4_Files_Received__c != null) {
                
                nextProj.Step4_Files_Received_Plus48__c = busDays.addBusinessHours(nextProj.Step4_Files_Received__c, 48);
                System.debug('===========>>> updateStep4FilesReceivedPlus48, nextProj: '+nextProj.Id+', Step4 Files+48: '+nextProj.Step4_Files_Received_Plus48__c);
            }
        }
    }

    // Send status emails based on the statusRecipientMap
    // Some recipients are Contacts
    // Recipients who are not a Contact require a dummy Contact
    // If project was created with the external API, it was not be in the oldProjMap and will have a phase of
    // 'Step5' or 'Step6'
    public void sendStatusChangeEmails (List <Project_Projects__c> newProjs, Map <ID, Project_Projects__c> oldIDProjMap, Boolean isInsert) {

        System.debug('=============>>> sendStatusChangeEmails, firstInvocation: '+firstInvocation);
        if (TriggerUtils.firstInvocation) {
            TriggerUtils.firstInvocation = false;
        }
        else {
            // If false, this trigger is being invoked for the 2nd consecutive time
            // due to a workflow.
            return;
        }

        // Get List of all changed Project IDs for making bulk queries
        List <ID> projIDs = new List <ID> ();
        Map <ID, Map <String, String>> projIDOppEmailMap = new Map <ID, Map <String, String>> ();
        for (Project_Projects__c nextProj : newProjs) {
            //System.debug('=============>>> Next project: '+nextProj.Id + 
            //                          ', old invoke: ' + oldIDProjMap.get(nextProj.Id).Invoke_Trigger__c+
            //                          ', new invoke: ' + nextProj.Invoke_Trigger__c);
            // The checkbox Invoke_Trigger__c is usually false
            // It is set to true by workflows on project
            // If true, this trigger is being invoked for the 2nd consecutive time
            // by the workflow.  In phase 2 Reset the checkbox and skip the project,
            // preferable to using a static variable.
            projIDs.add(nextProj.Id);
        }
        
        List <Project_Projects__c> relatedOpportunities = 
            [Select ID, Opportunity__r.Client_Project_Email__c, Opportunity__r.Client_DP_QA_Email__c
             From Project_Projects__c
             Where Id in :projIDs];
        
        for (Project_Projects__c nextProj : relatedOpportunities) {
            Map <String, String> nextMap = new Map <String, String> {
                    '{Opportunity.Client_Project_Email__c}'=>nextProj.Opportunity__r.Client_Project_Email__c,
                    '{Opportunity.Client_DP_QA_Email__c}'=>nextProj.Opportunity__r.Client_DP_QA_Email__c
                };
            projIDOppEmailMap.put(nextProj.Id, nextMap);
        }

        // Get all Project Contacts associated with these Projects
        // Where role is Detail/Other
        // One to many relationship between project and Detail/Other
        Map <ID, Set <ID>> projIDDetailOtherIDSetMap = new Map <ID, Set <ID>> ();
        Map <ID, Contact> contactIDDetailOtherMap = new Map  <ID, Contact> ();
        
        List <Project_Contact__c> cpoList =
            [Select Id, Project_Project__c, Contact__c
             From Project_Contact__c 
             Where Project_Project__c in :projIDs
                   and Contact_Role__c in :detailOtherSet
             order by Project_Project__c];
        
        if (cpoList != null && cpoList.size() > 0) {
            Set <ID> pcIDs = new Set <ID> ();
            ID lastProjID = cpoList[0].Project_Project__c;
            Set <ID> contactIDs = new Set <ID> ();
            for (Project_Contact__c nextPC : cpoList) {
                if (lastProjID != nextPC.Project_Project__c) {
                    projIDDetailOtherIDSetMap.put(lastProjID, pcIDs);
                    pcIDs = new Set<ID> ();
                }
                pcIDs.add(nextPC.Contact__c);
                contactIDs.add(nextPC.Contact__c); 
            }
            projIDDetailOtherIDSetMap.put(lastProjID, pcIDs);
            
            // this is a map from the contact ID to the contact record
            contactIDDetailOtherMap = new Map  <ID, Contact>([select Id, Email, Name from Contact where Id in :contactIDs]);
            System.debug('=============>>> contactIDDetailOtherMap, size: '+contactIDDetailOtherMap.size());
        }
        
        // Get all Project Contacts associated with these Projects
        // Where role is Overview
        // One to many relationship between project and Overview
        Map <ID, Set <ID>> projIDOverviewIDSetMap = new Map <ID, Set <ID>> ();
        Map <ID, Contact> contactIDOverviewMap = new Map  <ID, Contact> ();
        
        List <Project_Contact__c> pcList =
            [Select Id, Project_Project__c, Contact__c
             From Project_Contact__c 
             Where Project_Project__c in :projIDs
                   and Contact_Role__c = 'Overview'
             order by Project_Project__c];
        
        if (pcList != null && pcList.size() > 0) {
            Set <ID> pcIDs = new Set <ID> ();
            ID lastProjID = pcList[0].Project_Project__c;
            Set <ID> contactIDs = new Set <ID> ();
            for (Project_Contact__c nextPC : pcList) {
                if (lastProjID != nextPC.Project_Project__c) {
                    projIDOverviewIDSetMap.put(lastProjID, pcIDs);
                    pcIDs = new Set<ID> ();
                }
                pcIDs.add(nextPC.Contact__c);
                contactIDs.add(nextPC.Contact__c); 
            }
            projIDOverviewIDSetMap.put(lastProjID, pcIDs);
            
            // this is a map from the contact ID to the contact record
            contactIDOverviewMap = new Map  <ID, Contact>([select Id, Email, Name from Contact where Id in :contactIDs]);
        }
        
        messages = new List <Messaging.SingleEmailMessage> ();

        for (Project_Projects__c nextProj : newProjs) {
                        
            // Send status change emails
            String oldStatus = null;
            if (oldIDProjMap != null && oldIDProjMap.get(nextProj.Id) != null) oldStatus = oldIDProjMap.get(nextProj.Id).Status__c;

            System.debug('=============>>> nextProj: '+nextProj.Name+', isInsert: '+isInsert+', status: '+nextProj.Status__c+', oldStatus: '+oldStatus);
            if ((oldStatus != null && !oldStatus.equals('') && nextProj.Status__c != null && !nextProj.Status__c.equals(oldStatus)) ||
                (isInsert && nextProj.Status__c != null && (nextProj.Status__c.equals('Step5') || nextProj.Status__c.equals('QA Sign Off')))) {
                
                if (isInsert) System.debug('=============>>> This is a new project: '+nextProj.Status__c);
                else System.debug('=============>>> Status changed: '+nextProj.Status__c + ', old status: ' + oldIDProjMap.get(nextProj.Id).Status__c);
                
                // Get the list of template, recipients 
                List<String> templateRecipientList = statusTemplateRecipientMap.get(nextProj.Status__c);

                if (templateRecipientList != null) {

                    Set <String> emailAddresses = new Set <String> ();
                    Set <Contact> emailContacts = new Set <Contact> ();
    
                    // First element is template
                    EmailTemplate etemplate = lookupEmailTemplate(templateRecipientList[0], nextProj.Project_Type_Category__c);
                                        
                    // Get all recipients
                    for (Integer i=1; i<templateRecipientList.size(); i++) {

                        System.debug('============>>> next email recipient: '+templateRecipientList[i]);

                            if (templateRecipientList[i].contains('@')) {
                                String targetEmail = ProjectEmailAddresses.get(templateRecipientList[i]);
                                System.debug('============>>> email '+templateRecipientList[i]+', address: '+targetEmail);
                                if (targetEmail != null && !targetEmail.equals('')) {
                                    emailAddresses.add(targetEmail);
                                }
                            }
                            else if (templateRecipientList[i].equals('Detail/Other')) {
                                System.debug('============>>> email Detail/Other');
                                
                                if (projIDDetailOtherIDSetMap.get(nextProj.Id) != null) {
                                        System.debug('============>>> email Detail/Other, set: '+projIDDetailOtherIDSetMap.get(nextProj.Id));
                                    
                                    for (ID nextCPOID : projIDDetailOtherIDSetMap.get(nextProj.Id)) {
                                        System.debug('============>>> email Detail/Other, nextCPOID: '+nextCPOID);
                                        System.debug('============>>> email Detail/Other, '+contactIDDetailOtherMap.get(nextCPOID).Name+', email: '+contactIDDetailOtherMap.get(nextCPOID).Email);
                                        emailContacts.add(contactIDDetailOtherMap.get(nextCPOID));
                                    }
                                }
                            }
                            else if (templateRecipientList[i].equals('Overview')) {
                                System.debug('============>>> email Overview');
                                
                                if (projIDOverviewIDSetMap.get(nextProj.Id) != null) {

                                    for (ID nextOverviewID : projIDOverviewIDSetMap.get(nextProj.Id)) {
                                        System.debug('============>>> email Overview, '+contactIDOverviewMap.get(nextOverviewID).Name+', email: '+contactIDOverviewMap.get(nextOverviewID).Email);
                                        emailContacts.add(contactIDOverviewMap.get(nextOverviewID));
                                    }
                                }
                            }
                            else {
                                if (projIDOppEmailMap.get(nextProj.Id) != null) {
                                    String targetEmail = projIDOppEmailMap.get(nextProj.Id).get(templateRecipientList[i]);
                                    System.debug('============>>> email '+templateRecipientList[i]+', address: '+targetEmail);
                                    if (targetEmail != null && !targetEmail.equals('')) {
                                        emailAddresses.add(targetEmail);
                                    }                               
                                }
                            }
                        }
                        
                        // email is added to messages
                        Messaging.SingleEmailMessage newMessage = createEmail(nextProj, emailContacts, emailAddresses, etemplate);
                        if (newMessage != null) messages.add(newMessage);
                    }
                    
                }               
                
                // Send Received_Link date change email
                // This sends template C to EmailType1 and EmailType2
                if (oldIDProjMap != null && oldIDProjMap.get(nextProj.Id) != null && 
                    oldIDProjMap.get(nextProj.Id).Received_Link__c != nextProj.Received_Link__c
                    && nextProj.Project_Type_Category__c.startsWith('Status2')) {
    
                    Set <String> emailAddresses = new Set <String> ();
                    
                    System.debug('=============>>> Received_Link__c filled in: '+nextProj.Received_Link__c + ', old date: ' + oldIDProjMap.get(nextProj.Id).Received_Link__c);
        
                    String appsTargetEmail = ProjectEmailAddresses.get('EmailType1@Project.com');
                    System.debug('============>>> send to '+appsTargetEmail);
                    if (appsTargetEmail != null && !appsTargetEmail.equals('')) emailAddresses.add(appsTargetEmail);        
    
                    String qaTargetEmail = ProjectEmailAddresses.get('EmailType2@Project.com');
                    System.debug('============>>> send to '+qaTargetEmail);
                    if (qaTargetEmail != null && !qaTargetEmail.equals('')) emailAddresses.add(qaTargetEmail);
                    
                    // email is added to messages
                    Messaging.SingleEmailMessage newMessage = createEmail(nextProj, null, emailAddresses, lookupEmailTemplate('C', nextProj.Project_Type_Category__c));
                    if (newMessage != null) messages.add(newMessage);
                }

            }
    
        System.debug('=============>>> Sending messages, size(): '+messages.size());
        if (messages.size() > 0) {
            Messaging.sendEmail(messages);
        }

        System.debug('=============>>> Deleting temp Contacts, size(): '+tempContacts.size());
        if (tempContacts.size() > 0) {
            delete tempContacts;
        }
        
        
    }
    
    // These templates have _Status1 and _Status2 versions
    private Set <String> templatesTwoTypes = new Set <String> {'A','G','H','I','J','K','M','N','O'};

    private EmailTemplate lookupEmailTemplate(String templateName, String projectTypeCategory) {
        
        String queryString = '';
        System.debug('============>>> templateName: '+templateName+', projectTypeCategory: '+projectTypeCategory+', queryString: '+queryString);
        
        if (templatesTwoTypes.contains(templateName)) {
            
            queryString = codeQueryMap.get(templateName);
            
            if (projectTypeCategory.startsWith('Status1')) { // Status1
                queryString += '_Status1';
            }
            else {
                queryString += '_Status2';
            }

        }
        else if (templateName.equals('C')) {
            queryString = 'C_TestLink%';
        }
        else {
            
            String [] parts = templateName.split('::');
            if (projectTypeCategory.startsWith('Status1')) { // Status1
                queryString = parts[2] + '_%_Status1';
            }
            else {
                queryString = parts[0] + '_%_Status2';
            }
            
        }
        System.debug('============>>> templateName: '+templateName+', projectTypeCategory: '+projectTypeCategory+', queryString: '+queryString);
        return [Select Id From EmailTemplate Where DeveloperName like :queryString];
    }


    private Messaging.SingleEmailMessage createEmail(Project_Projects__c project, Set <Contact> emailContacts, Set <String> emailRecipients, EmailTemplate template) {

        System.debug('============>>> createEmail, '+
            'contacts: '+(emailContacts == null ? 0 : emailContacts.size())+
            ', recipients: '+emailRecipients.size());
        if ( (emailContacts == null || emailContacts.size() < 1) && 
             (emailRecipients == null || emailRecipients.size() < 1) ) return null; 
        
        List <String> additionalEmails = new List <String> ();

        // if a Contact exists, use it for constructing the message
        if (emailContacts != null && emailContacts.size() > 0) {
            Contact recipientContact = null;
            for (Contact nextCon : emailContacts) {
                if (recipientContact == null) recipientContact = nextCon;
                else additionalEmails.add(nextCon.Email);
            }
            for (String nextRecip : emailRecipients) {
                additionalEmails.add(nextRecip);
            }
            return emailContact(project, recipientContact, additionalEmails, template);
        }
        else {
            for (String nextRecip : emailRecipients) {
                additionalEmails.add(nextRecip);
            }
            return emailUsingTempContact(project, additionalEmails, template);
        }
    }
    
    
    private Messaging.SingleEmailMessage emailContact(Project_Projects__c project, Contact target, String [] additional, EmailTemplate template) {

        //set the email properties
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        //mail.setSenderDisplayName(user.Name);
        mail.setTemplateId(template.id);
        mail.setTargetObjectId(target.Id);
        mail.setWhatId(project.Id);
        mail.setToAddresses(additional);
        //mail.setSaveAsActivity(false);

        return mail;
    }
    

    private Messaging.SingleEmailMessage emailUsingTempContact(Project_Projects__c project, String [] targets, EmailTemplate template) {

        Contact tempContact = new Contact();
        tempContact.Email = targets[0];
        tempContact.FirstName = '';
        tempContact.LastName = 'Project';
        insert tempContact;
        
        //set the email properties
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        
        //mail.setSenderDisplayName(user.Name);
        mail.setTemplateId(template.id);
        mail.setTargetObjectId(tempContact.Id);
        mail.setWhatId(project.Id);
        if (targets.size() > 1) {
            List <String> additional = new List <String> ();
            for (Integer i=1; i<targets.size(); i++) additional.add(targets[i]);
            mail.setToAddresses(additional);
        }
        //mail.setSaveAsActivity(false);
        
        tempContacts.add(tempContact);
        return mail;
    }


    public class BusinessDays {
 
        private List<Boolean> businessDay = new Boolean[7];
        private List<Time> startHours = new Time [7];
        private List<Time> endHours = new Time [7];
        private Date knownSunday = date.newInstance(2011, 12, 4);
     
        // Constructor creates businessDay array
        public BusinessDays(){
            BusinessHours bh = 
                [Select FridayStartTime,MondayStartTime,SaturdayStartTime,SundayStartTime,
                        ThursdayStartTime,TuesdayStartTime,WednesdayStartTime,
                        SundayEndTime,MondayEndTime,TuesdayEndTime,WednesdayEndTime,ThursdayEndTime,
                        FridayEndTime,SaturdayEndTime
                 From BusinessHours 
                 Where IsDefault=true];
            businessDay[0] = (bh.SundayStartTime != null);
            businessDay[1] = (bh.MondayStartTime != null);
            businessDay[2] = (bh.TuesdayStartTime != null);
            businessDay[3] = (bh.WednesdayStartTime != null);
            businessDay[4] = (bh.ThursdayStartTime != null);
            businessDay[5] = (bh.FridayStartTime != null);
            businessDay[6] = (bh.SaturdayStartTime != null);
            
            startHours[0] = bh.SundayStartTime;
            startHours[1] = bh.MondayStartTime;
            startHours[2] = bh.TuesdayStartTime;
            startHours[3] = bh.WednesdayStartTime;
            startHours[4] = bh.ThursdayStartTime;
            startHours[5] = bh.FridayStartTime;
            startHours[6] = bh.SaturdayStartTime;
            
            endHours[0] = bh.SundayEndTime;
            endHours[1] = bh.MondayEndTime;
            endHours[2] = bh.TuesdayEndTime;
            endHours[3] = bh.WednesdayEndTime;
            endHours[4] = bh.ThursdayEndTime;
            endHours[5] = bh.FridayEndTime;
            endHours[6] = bh.SaturdayEndTime;

            Integer i = 3;
            System.debug('============>>> init BusinessDays, businessDay['+i+']: '+businessDay[3] +
                         ', startHours['+i+']: ' + startHours[i] +
                         ', endHours['+i+']: ' + endHours[i]);
            i = 5;
            System.debug('============>>> init BusinessDays, businessDay['+i+']: '+businessDay[3] +
                         ', startHours['+i+']: ' + startHours[i] +
                         ', endHours['+i+']: ' + endHours[i]);
        }
     
        // Returns back date in numberOfHours business days
        // Returns back the next available business day/time, ignoring non business days
        // E.g. if startDate = Monday 4:00pm and business is open, returns Wednesday 4:00pm
        //      but if business is closed, returns next day at start of business 
        // Project wanted to return during business hours if received during business hours
        //   so if received Friday 3:00pm, returns Tues 3:00pm
        public Datetime addBusinessHours (Datetime startDate, integer numberOfHours) {
            System.debug('============>>> startDate : '+startDate.formatLong()+', startDate+48: '+startDate.addHours(numberOfHours).formatLong());

            // Day received index     
            Integer i = Math.mod(Math.abs(this.knownSunday.daysBetween(startDate.date())),7);

            System.debug('============>>> startDate: '+startDate.format()+', startHours[i]: '+startHours[i]+
                         ', endHours[i]'+endHours[i]+', businessDay[Math.mod(i, 7)]: '+businessDay[Math.mod(i, 7)]);
                         
            // Received on a business day during hours
            // Return in 2 days, ignoring non business days
            if ( businessDay[Math.mod(i, 7)] && 
                 startDate.time() >= startHours[i] &&
                 startDate.time() <= endHours[i] ) {
                return nextTwoBusinessDays(startDate);
            }
            // Received on a business day before hours
            else if ( businessDay[Math.mod(i, 7)] && 
                 startDate.time() < startHours[i] ) {
                Datetime returnDate = nextTwoBusinessDays(startDate);
                Integer j = Math.mod(Math.abs(this.knownSunday.daysBetween(returnDate.date())),7);
                return Datetime.newInstance( returnDate.date(), startHours[j] );
            }
            // Received on a business day after hours 
            // or received not a business day
            // Return at start time in 2 business days, ignoring non business days
            else {
                Datetime returnDate = nextBusinessDay(startDate.addDays(1));
                returnDate = nextTwoBusinessDays(returnDate);
                Integer j = Math.mod(Math.abs(this.knownSunday.daysBetween(returnDate.date())),7);
                return Datetime.newInstance( returnDate.date(), startHours[j] );
            }
        }

        // Counts forward 2 days, skipping non business days
        public Datetime nextTwoBusinessDays(Datetime d) {
            Integer i = Math.mod(Math.abs(this.knownSunday.daysBetween(d.date())),7);
            Integer counter = 0;
            Datetime returnDate = d;
            
            System.debug('============>>> nextTwoBusinessDays, '+
                                         'returnDate: '+returnDate.format()+
                                         ', businessDay[Math.mod(i, 7)]: '+businessDay[Math.mod(i, 7)]);

            while (counter < 2) {
                i++;
                returnDate = returnDate.addDays(1);
                if (businessDay[Math.mod(i, 7)]) {
                    counter++;
                }
            }

            System.debug('============>>> nextTwoBusinessDays->returning, '+
                                         'returnDate: '+returnDate.format()+
                                         ', i: '+i+
                                         ', businessDay[Math.mod(i, 7)]: '+businessDay[Math.mod(i, 7)]);

            return returnDate;
        }

        // Gets next business day, skipping non business days
        public Datetime nextBusinessDay(Datetime d) {
            Integer i = Math.mod(Math.abs(this.knownSunday.daysBetween(d.date())),7);
            Datetime returnDate = d;
            
            System.debug('============>>> nextBusinessDay, '+
                                         'returnDate: '+returnDate.format()+
                                         ', businessDay[Math.mod(i, 7)]: '+businessDay[Math.mod(i, 7)]);

            while (!businessDay[Math.mod(i, 7)]) {
                i++;
                returnDate = returnDate.addDays(1);
            }

            System.debug('============>>> nextBusinessDay->returning, '+
                                         'returnDate: '+returnDate.format()+
                                         ', i: '+i+
                                         ', businessDay[Math.mod(i, 7)]: '+businessDay[Math.mod(i, 7)]);

            return returnDate;
        }
    }

}
