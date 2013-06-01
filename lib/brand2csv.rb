#!/usr/bin/env ruby
# encoding: utf-8
require 'rubygems' if /^1\.8/.match(RUBY_VERSION)
require "brand2csv/version"
require 'mechanize'
require 'prettyprint'
require 'optparse'
require 'csv'
require 'logger'

module Brand2csv

  class Marke < Struct.new(:name, :markennummer, :inhaber, :land, :hinterlegungsdatum, :zeile_1, :zeile_2, :zeile_3, :zeile_4, :zeile_5, :plz, :ort)
  end

  class Swissreg
    
      # Weitere gesehene Fehler
    BekannteFehler = 
          ['Das Datum ist ung', # ültig'
           'Vereinfachte Trefferliste anzeigen',
            'Es wurden keine Daten gefunden.',
            'Die Suchkriterien sind teilweise unzul', # ässig',
            'Geben Sie mindestens ein Suchkriterium ein',
            'Die Suche wurde abgebrochen, da die maximale Suchzeit von 60 Sekunden',
           'Erweiterte Suche',
          ]
    Base_uri = 'https://www.swissreg.ch'
    Start_uri = "#{Base_uri}/srclient/faces/jsp/start.jsp"
    Sr1      = "#{Base_uri}/srclient/faces/jsp/trademark/sr1.jsp"
    Sr2      = "#{Base_uri}/srclient/faces/jsp/trademark/sr2.jsp"
    Sr3      = "#{Base_uri}/srclient/faces/jsp/trademark/sr3.jsp"
    Sr30     = "#{Base_uri}/srclient/faces/jsp/trademark/sr30.jsp"
    Sr300    = "#{Base_uri}/srclient/faces/jsp/trademark/sr300.jsp"
    AddressRegexp = /^(\d\d\d\d)\W*(.*)/
    LineSplit     = ', '
    DefaultCountry = 'Schweiz'
    # Angezeigte Spalten "id_swissreg:mainContent:id_ckbTMChoice"
    TMChoiceFields = [ 
            "tm_lbl_tm_text", # Marke
            # "tm_lbl_state"], # Status
            # "tm_lbl_nizza_class"], # Nizza Klassifikation Nr.
            # "tm_lbl_no"], # disabled="disabled"], # Nummer
            "tm_lbl_applicant", # Inhaber/in
            "tm_lbl_country", # Land (Inhaber/in)
            # "tm_lbl_agent", # Vertreter/in
            # "tm_lbl_licensee"], # Lizenznehmer/in
            "tm_lbl_app_date", # Hinterlegungsdatum
            ]
    # Alle Felder mit sprechenden Namen
    # ["id_swissreg:mainContent:id_txf_tm_no", nummer],# Marken Nr
    # ["id_swissreg:mainContent:id_txf_app_no", ""],                       # Gesuch Nr.
    # ["id_swissreg:mainContent:id_txf_tm_text", marke],
    # ["id_swissreg:mainContent:id_txf_applicant", ""],                    # Inhaber/in
    # ["id_swissreg:mainContent:id_cbxCountry", "_ALL"], # Auswahl Länder _ALL
    # ["id_swissreg:mainContent:id_txf_agent", ""],                         # Vertreter/in
    # ["id_swissreg:mainContent:id_txf_licensee", ""], # Lizenznehmer
    # ["id_swissreg:mainContent:id_txf_nizza_class", ""], # Nizza Klassifikation Nr.
    #      # ["id_swissreg:mainContent:id_txf_appDate", timespan], # Hinterlegungsdatum
    # ["id_swissreg:mainContent:id_txf_appDate",  "%s" % timespan] ,
    # ["id_swissreg:mainContent:id_txf_expiryDate", ""], # Ablauf Schutzfrist
    # Markenart: Individualmarke 1 Kollektivmarke 2 Garantiemarke 3
    # ["id_swissreg:mainContent:id_cbxTMTypeGrp", "_ALL"],  # Markenart
    # ["id_swissreg:mainContent:id_cbxTMForm", "_ALL"],  # Markentyp
    # ["id_swissreg:mainContent:id_cbxTMColorClaim", "_ALL"],  # Farbanspruch
    # ["id_swissreg:mainContent:id_txf_pub_date", ""], # Publikationsdatum

    # info zu Publikationsgrund id_swissreg:mainContent:id_ckbTMPubReason
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "1"], #Neueintragungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "2"], #Berichtigungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "3"], #Verlängerungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "4"], #Löschungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "5"], #Inhaberänderungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "6"], #Vertreteränderungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "7"], #Lizenzänderungen
    # ["id_swissreg:mainContent:id_ckbTMPubReason", "8"], #Weitere Registeränderungen
    # ["id_swissreg:mainContent:id_ckbTMEmptyHits", "0"],  # Leere Trefferliste anzeigen
    # ["id_swissreg:mainContent:id_ckbTMState", "1"], # "Hängige Gesuche 1
    #      # ["id_swissreg:mainContent:id_ckbTMState", "2"], # "Gelöschte Gesuche 2
    # ["id_swissreg:mainContent:id_ckbTMState", "3"], # aktive Marken 3 
    #      # ["id_swissreg:mainContent:id_ckbTMState", "4"], # gelöschte Marken 4

    
    MaxZeilen = 5
    HitsPerPage = 250
    LogDir = 'mechanize'
    
    attr_accessor :marke, :results, :timespan
    
    def initialize(timespan, marke = nil)
      @timespan = timespan
      @marke = marke
      @number = nil
      
      @agent = Mechanize.new { |agent|
        agent.user_agent = 'Mozilla/5.0 (X11; Linux x86_64; rv:16.0) Gecko/20100101 Firefox/16.0'
        agent.verify_mode = OpenSSL::SSL::VERIFY_NONE
        FileUtils.makedirs(LogDir) if $VERBOSE or defined?(RSpec)
        agent.log = Logger.new("#{LogDir}/mechanize.log") if $VERBOSE
      }
      @results = []
      @errors  = Hash.new
      @lastDetail =nil
      @counterDetails = 0
      if false # force some values
        # asp* => 138 records werden geholt
        # a* => Es wurden 25,490 Treffer gefunden. Davon werden 10000 zufällig ausgewählte Schutztitel angezeigt. Bitte schränken Sie Ihre Suche weiter ein.
        #       Ab 501 Treffer wird eine vereinfachte Trefferliste angezeigt.  
        # asp* => 138 records werden geholt

        @marke = 'zzzyyzzzzyzzyz*' # => Fehlermeldung: Es wurden keine Daten gefunden
        @marke = 'aspira' 
        # @number = '500000' # für Weihnachten
        @number = ' 601416' # für aspira
  #      @marke = "*WEIH*"
        @timespan = nil
      end
    end
    
    def writeResponse(filename)
      if defined?(RSpec) or $VERBOSE
        ausgabe = File.open(filename, 'w+')
        ausgabe.puts @agent.page.body
        ausgabe.close
      else
        puts "Skipping writing #{filename}" if $VERBOSE
      end
    end

    def view_state(response)
      if /^1\.8/.match(RUBY_VERSION)
        match = /javax.faces.ViewState.*?value="([^"]+)"/u.match(response)
      else
        match = /javax.faces.ViewState.*?value="([^"]+)"/u.match(response.force_encoding('utf-8'))
      end
      match ? match[1] : ""
    end

    def checkErrors(body)
      BekannteFehler.each {
      |errMsg|
        if body.to_s.index(errMsg)
          puts "Tut mir leid. Suche wurde mit Fehlermeldung <#{errMsg}> abgebrochen."
          exit 2
        end
      }
    end
    
    UseClick = false
    
    def parse_swissreg(timespan = @timespan,  # sollte 377 Treffer ergeben, für 01.06.2007-10.06.2007, 559271 wurde in diesem Zeitraum registriert
                      marke = @marke,    
                      nummer =@number) #  nummer = "559271" ergibt genau einen treffer

      # discard this first response
      # swissreg.ch could not handle cookie by redirect.
      # HTTP status code is also strange at redirection.
      @agent.get Start_uri  # get a cookie for the session
      content = @agent.get_file Start_uri
      writeResponse("#{LogDir}/start.jsp")
      # get only view state
      @state = view_state(content)
      data = [
        ["autoScroll", "0,0"],
        ["id_swissreg:_link_hidden_", ""],
        ["id_swissreg_SUBMIT", "1"],
        ["id_swissreg:_idcl", "id_swissreg_sub_nav_ipiNavigation_item0"],
        ["javax.faces.ViewState", @state],
      ]
      if UseClick 
        Swissreg::setAllInputValue(@agent.page.forms.first, data)
        @agent.page.forms.first.submit      
      else
        @agent.post(Start_uri, data)  
      end
      writeResponse("#{LogDir}/start2.jsp")
      # Navigation with mechanize like this fails and returns to the home page
      # @agent.page.link_with(:id => "id_swissreg_sub_nav_ipiNavigation_item0").click
      
      data = [
        ["autoScroll", "0,0"],
        ["id_swissreg:_link_hidden_", ""],
        ["id_swissreg_SUBMIT", "1"],
        ["id_swissreg:_idcl", "id_swissreg_sub_nav_ipiNavigation_item0_item3"],
        ["javax.faces.ViewState", @state],
      ]
      # sr1 ist die einfache suche, sr3 die erweiterte Suche
      if UseClick 
        Swissreg::setAllInputValue(@agent.page.forms.first, data)
        @agent.page.forms.first.submit      
      else
        @agent.post(Sr3, data)
      end
      writeResponse("#{LogDir}/sr3.jsp")
      
      # Fill out form values
      selectedPublicationStates =  ['1', '3']
      @agent.page.form('id_swissreg').checkboxes.each{ 
        |box| 
        TMChoiceFields.index(box.value) ? box.check : box.uncheck 
        # box.check if $VERBOSE
        # select all publication reasons
        box.check if /id_ckbTMPubReason/.match(box.name)
        # select all publication states or accept default states
        # box.check if /id_ckbTMState/.match(box.name) 
        if /id_ckbTMState/.match(box.name) 
          if selectedPublicationStates.index(box.value)
            puts "Select id_ckbTMState #{box.value}" if $VERBOSE
            box.check
          else
            box.uncheck
          end
        end
      }
      if $VERBOSE and false # fill all details for marke  567120        
        # Felder, welche nie bei der Antwort auftauchen
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_licensee') { |x| x.value = 'BBB Inc*' }
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_expiryDate') { |x| x.value = timespan }
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_pub_date') { |x| x.value = timespan }
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_nizza_class') { |x| x.value = '9' }      
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_agent') { |x| x.value = 'Marc Stucki*' }
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_cbxCountry') { |x| x.value = 'CH' }  # 'CH' or '_ALL'

        # Felder, welche im Resultat angezeigt werden
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_applicant') { |x| x.value = 'ASP ATON*' } #inhaber
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_tm_no') { |x| x.value = "567120" }
        @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_app_no') { |x| x.value = '50329/2008' }
      end
      
      # Feld, welches im Resultat angezeigt wird
      @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_tm_text') { |x| x.value = @marke}
      
      # Felder, welches nie bei der Antwort auftaucht. Ein Versuch .gsub('.', '%2E') schlug ebenfalls fehl!
      @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_txf_appDate') { |x| x.value = timespan}
      
      # Feld, welches ebenfalls berücksichtigt wird
      @agent.page.form('id_swissreg').field(:name => 'id_swissreg:mainContent:id_cbxHitsPerPage') { |x| x.value = HitsPerPage }
      @agent.page.form('id_swissreg').field(:name => 'autoScroll') { |x| x.value = '0,0' }
      
      if $VERBOSE
        puts "State of searchForm is:"
        @agent.page.form('id_swissreg').fields.each{ |f| puts "field: #{f.name}: #{f.value}"}  
        @agent.page.form('id_swissreg').checkboxes.each{ |box| puts "#{box.name} checked? #{box.checked}"} 
      end
      
        @criteria = [
          ["autoScroll", "0,829"],
          ["id_swissreg:_link_hidden_", ""],
          ["id_swissreg:mainContent:id_ckbTMState", "1"], # "Hängige Gesuche 1
    #      ["id_swissreg:mainContent:id_ckbTMState", "2"], # "Gelöschte Gesuche 2
          ["id_swissreg:mainContent:id_ckbTMState", "3"], # aktive Marken 3 
    #      ["id_swissreg:mainContent:id_ckbTMState", "4"], # gelöschte Marken 4
          ["id_swissreg:mainContent:id_cbxCountry", "_ALL"], # Auswahl Länder _ALL
#            ["id_swissreg:mainContent:id_txf_tm_no", ""],  # Marken Nr
          ["id_swissreg:mainContent:id_txf_tm_no", nummer],# Marken Nr
          ["id_swissreg:mainContent:id_txf_app_no", ""],                       # Gesuch Nr.
          ["id_swissreg:mainContent:id_txf_tm_text", marke],
          ["id_swissreg:mainContent:id_txf_applicant", ""],                    # Inhaber/in
          ["id_swissreg:mainContent:id_txf_agent", ""],                         # Vertreter/in
          ["id_swissreg:mainContent:id_txf_licensee", ""], # Lizenznehmer
          ["id_swissreg:mainContent:id_txf_nizza_class", ""], # Nizza Klassifikation Nr.
    #      ["id_swissreg:mainContent:id_txf_appDate", timespan], # Hinterlegungsdatum
          ["id_swissreg:mainContent:id_txf_appDate", timespan] ,
          ["id_swissreg:mainContent:id_txf_expiryDate", ""], # Ablauf Schutzfrist
          # Markenart: Individualmarke 1 Kollektivmarke 2 Garantiemarke 3
          ["id_swissreg:mainContent:id_cbxTMTypeGrp", "_ALL"],  # Markenart
          ["id_swissreg:mainContent:id_cbxTMForm", "_ALL"],  # Markentyp
          ["id_swissreg:mainContent:id_cbxTMColorClaim", "_ALL"],  # Farbanspruch
          ["id_swissreg:mainContent:id_txf_pub_date", ""], # Publikationsdatum
          
        # info zu Publikationsgrund id_swissreg:mainContent:id_ckbTMPubReason
          ["id_swissreg:mainContent:id_ckbTMPubReason", "1"], #Neueintragungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "2"], #Berichtigungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "3"], #Verlängerungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "4"], #Löschungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "5"], #Inhaberänderungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "6"], #Vertreteränderungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "7"], #Lizenzänderungen
          ["id_swissreg:mainContent:id_ckbTMPubReason", "8"], #Weitere Registeränderungen
#            ["id_swissreg:mainContent:id_ckbTMEmptyHits", "0"],  # Leere Trefferliste anzeigen
                      
          # "id_swissreg:mainContent:id_cbxFormatChoice" 2 = Publikationsansicht 1 = Registeransicht
          ["id_swissreg:mainContent:id_cbxFormatChoice", "1"],
          ["id_swissreg:mainContent:id_cbxHitsPerPage", HitsPerPage],   # Treffer pro Seite
        ]
        TMChoiceFields.each{ | field2display| @criteria << ["id_swissreg:mainContent:id_ckbTMChoice", field2display] }
                                                            # id_swissreg:mainContent:id_ckbTMChoice  tm_lbl_tm_text
        puts "Marke ist #{marke}" if marke               # Wortlaut der Marke
        puts "Hinterlegungsdatum ist #{timespan}"  if $VERBOSE and timespan   
        puts "nummer ist #{timespan}" if nummer
        @criteria <<   ["id_swissreg:mainContent:sub_fieldset:id_submit", "suchen"]
        @criteria <<    ["id_swissreg_SUBMIT", "1"]
        @criteria <<    ["id_swissreg:_idcl", ""]
        @criteria <<    ["id_swissreg:_link_hidden_", ""]
        @criteria <<    ["javax.faces.ViewState", @state]
        
      if true # UseClick 
 #       Swissreg::setAllInputValue(@agent.page.forms.first, @criteria)
#        setPublicationStates(@agent.page.form('id_swissreg'))
        @agent.page.form('id_swissreg').click_button(@agent.page.form('id_swissreg').button_with(:value => "suchen"))
      else # use post        
        writeResponse("#{LogDir}/vor_post_sr3.jsp")
        @agent.post(Sr3, @criteria)
        writeResponse("#{LogDir}/erweiterte_suche.html")
        @agent.page.form('id_swissreg').click_button(@agent.page.form('id_swissreg').button_with(:value => "suchen"))
      end
      # Hier sollten eigentlich alle Felder auftauchen, wie
      # Marke=asp*; Land (Inhaber/in)=Schweiz; Markenart=Alle; Markentyp=Alle; Farbanspruch=Alle; Publikationsgrund= Neueintragungen, Berichtigungen, Verlängerungen, Löschungen, Inhaberänderungen, Vertreteränderungen, Lizenzänderungen, Weitere Registeränderungen; Status= hängige Gesuche, aktive Marken      
      writeResponse("#{LogDir}/resultate.jsp")
    end

    # the number is only passed to facilitate debugging
    # lines are the address lines 
    def Swissreg::parseAddress(number, lines)
      ort = nil
      plz = nil
      
      # Search for plz/address
      1.upto(lines.length-1).each  {
        |cnt|
          if    m = AddressRegexp.match(lines[cnt])
            lines[cnt+1] = nil
            plz = m[1]; ort = m[2]
            cnt.upto(MaxZeilen-1).each{ |cnt2| lines[cnt2] = nil }
            break
          end
      }
      unless plz
        puts "Achtung! Konnte Marke #{number} mit Inhaber #{lines.inspect} nicht parsen" if $VERBOSE
        return nil,   nil,     nil,     nil,     nil,     nil,     nil, nil
      end
      # search for lines with only digits
      found = false
      1.upto(lines.length-1).each  {
        |cnt|
          break if lines[cnt] == nil
          if /^\d*$/.match(lines[cnt])
            found = true
            if lines[cnt+1] == nil
              found = 'before'
              lines[cnt-1] += LineSplit + lines[cnt]
              lines.delete_at(cnt)
            else
              found = 'after'
              lines[cnt] += LineSplit + lines[cnt+1]
              lines.delete_at(cnt+1)
            end
          end        
      }
      puts "found #{found}: #{lines.inspect}" if found and $VERBOSE
      return lines[0], lines[1], lines[2], lines[3], lines[4], plz, ort
    end

    def Swissreg::getInputValuesFromPage(body) # body of HTML page
      contentData = []
      body.search('input').each{ |input| 
                                # puts "name: #{input.attribute('name')} value #{input.attribute('value')}" 
                                contentData << [ input.attribute('name').to_s, input.attribute('value').to_s ]
                                }
      contentData
    end
    
    # return value of an array of POST values
    def Swissreg::inputValue(values, key)
      values.each{ |val| 
                   return val[1] if key.eql?(val[0])
                }
      return nil
    end
    
    # set value for a key of an array of POST values
    def Swissreg::setInputValue(values, key, newValue)
      values.each{ |val| 
                    if key.eql?(val[0])
                      val[1] = newValue
                      return
                    end
                }
      return
    end
    
    def Swissreg::setAllInputValue(form, values)
      values.each{ |newValue|
#                 puts "x: 0 #{ newValue[0].to_s} 1 #{newValue[1].to_s}"
                    form.field(:name => newValue[0].to_s) { |elem| 
                                                            next if elem == nil # puts "Cannot set #{newValue[0].to_s}"
                                                            elem.value = newValue[1].to_s 
                                                          }
                 }
    end

    def Swissreg::getMarkenInfoFromDetail(doc)
      marke = nil
      number = 'invalid'
      bezeichnung = nil
      inhaber = nil
      hinterlegungsdatum = nil
      zeilen = []
      doc.xpath("//html/body/form/div/div/fieldset/div/table/tbody/tr").each{ 
        |x|
          if x.children.first.text.eql?('Marke')
            if x.children[1].text.index('Markenabbildung')
              # we must fetch the link to the image
              bezeichnung =  x.children[1].elements.first.attribute('href').text
            else # we got a trademark
              bezeichnung = x.children[1].text 
            end
          end
          if x.children.first.text.eql?('Inhaber/in')
            inhaber = />(.*)<\/td/.match(x.children[1].to_s)[1].gsub('<br>',LineSplit)
            x.children[1].children.each{ |child| zeilen << child.text unless child.text.length == 0 } # avoid adding <br>
          end
          hinterlegungsdatum = x.children[1].text if x.children.first.text.eql?('Hinterlegungsdatum')           
          number = x.children[1].text if x.children.first.text.eql?('Gesuch Nr.')           
      }
      zeile_1, zeile_2, zeile_3, zeile_4, zeile_5, plz, ort = Swissreg::parseAddress(number, zeilen)
      marke = Marke.new(bezeichnung, number,  inhaber,  DefaultCountry,  hinterlegungsdatum, zeile_1, zeile_2, zeile_3, zeile_4, zeile_5, plz, ort )
    end
    
    def Swissreg::emitCsv(results, filename='ausgabe.csv')
      return if results == nil or results.size == 0
      if /^1\.8/.match(RUBY_VERSION)
        ausgabe = File.open(filename, 'w+')
        # Write header
        s=''
        results[0].members.each { |member| s += member + ';' }
        ausgabe.puts s.chop
        # write all line
        results.each{ 
          |result| 
            s = ''
            result.members.each{ |member| 
                                  unless eval("result.#{member}") 
                                    s += ';'
                                  else
                                    value = eval("result.#{member.to_s}")
                                    value = "\"#{value}\"" if value.index(';')
                                    s += value + ';' 
                                  end
                               }
            ausgabe.puts s.chop
        }        
        ausgabe.close
      else
        
        CSV.open(filename,  'w', :headers=>results[0].members,
                                  :write_headers => true,
                                  :col_sep => ';'
                                ) do |csv| results.each{ |x| csv << x }
        end
      end
    end
    
    class Swissreg::Vereinfachte
      attr_reader :links2details, :trademark_search_id, :inputData, :firstHit, :nrHits, :nrSubPages, :pageNr
      HitRegexpDE = /Seite (\d*) von ([\d']*) - Treffer ([\d']*)-([\d']*) von ([\d']*)/
      Vivian      = 'id_swissreg:mainContent:vivian'
      
      # Parse a HTML page from swissreg sr3.jsp
      # There we find info like "Seite 1 von 26 - Treffer 1-250 von 6'349" and upto 250 links to details
      def initialize(doc)
        @inputData = []
        m = HitRegexpDE.match(doc.text)
        @pageNr = m[1].sub("'", '').to_i
        @nrSubPages = m[2].sub("'", '').to_i
        @firstHit = m[3].sub("'", '').to_i
        @nrHits = m[5].sub("'", '').to_i
        @trademark_search_id = Swissreg::inputValue(Swissreg::getInputValuesFromPage(doc), Vivian)
        @links2details = []
        doc.search('input').each{ |input| 
                                # puts "name: #{input.attribute('name')} value #{input.attribute('value')}" if $VERBOSE
                                @inputData << [ input.attribute('name').to_s, input.attribute('value').to_s ]
                                }
        
        @state = Swissreg::inputValue(Swissreg::getInputValuesFromPage(doc),  'javax.faces.ViewState')
        doc.search('a').each{ 
          |link| 
            if m = /d_swissreg:mainContent:data:(\d*):tm_no_detail:id_detail/i.match(link.attribute('id'))
              # puts "XXX #{link.attribute('onclick').to_s} href: #{link.attribute('href').to_s} value #{link.attribute('value').to_s}" if $VERBOSE
              m  = /'tmMainId','(\d*)'/.match(link.attribute('onclick').to_s)
              tmMainId = m[1].to_i
              @links2details << tmMainId
            end      
        }      
      end
      
      def getPostDataForDetail(position, id)
        [
          [ "autoScroll", "0,0"],
          [ "id_swissreg:mainContent:sub_options_result:sub_fieldset:cbxHitsPerPage", "#{HitsPerPage}"],
          [ "id_swissreg:mainContent:vivian", @trademark_search_id],
          [ "id_swissreg_SUBMIT", "1"],
          [ "id_swissreg:_idcl", "id_swissreg:mainContent:data:#{position}:tm_no_detail:id_detail", ""],
          [ "id_swissreg:mainContent:scroll_1", ""],
          [ "tmMainId", "#{id}"],
          [ "id_swissreg:_link_hidden_ "],
          [ "javax.faces.ViewState", @state]
        ]
      end

      def getPostDataForSubpage(pageNr)
        [
          [ "autoScroll", "0,0"],
          [ "id_swissreg:mainContent:sub_options_result:sub_fieldset:cbxHitsPerPage", "#{HitsPerPage}"],
          [ "id_swissreg:mainContent:vivian", @trademark_search_id],
          [ "id_swissreg_SUBMIT", "1"],
          [ "id_swissreg:_idcl", "id_swissreg:mainContent:scroll_1idx#{pageNr}"],
          [ "id_swissreg:mainContent:scroll_1", "idx#{pageNr}"],
          [ "tmMainId", ""],
          [ "id_swissreg:_link_hidden_ "],
          [ "javax.faces.ViewState", @state]
        ]
      end
      
    end
    
    def getAllHits(filename = nil, pageNr = 1)
      if filename && File.exists?(filename)
        doc = Nokogiri::Slop(File.open(filename))        
      else
        body = @agent.page.body
        body.force_encoding('utf-8') unless /^1\.8/.match(RUBY_VERSION)
        doc = Nokogiri::Slop(body)
        filename = "#{LogDir}/vereinfachte_#{pageNr}.html"
        writeResponse(filename)
      end
      
      einfach = Swissreg::Vereinfachte.new(doc)
      puts "#{Time.now.strftime("%H:%M:%S")} status: fetch #{pageNr} of #{einfach.nrSubPages}"
      subPage2Fetch = pageNr + 1
      data2 = einfach.getPostDataForSubpage(subPage2Fetch).clone
      if (HitsPerPage < einfach.nrHits - einfach.firstHit)
        itemsToFetch = HitsPerPage
      else
        itemsToFetch = einfach.nrHits - einfach.firstHit
      end
      0.upto(itemsToFetch-1) {
        |position|
        id       = einfach.links2details[position]
        nextId   = einfach.firstHit.to_i - 1 + position.to_i
        data3 = einfach.getPostDataForDetail(nextId, id)
        Swissreg::setAllInputValue(@agent.page.forms.first, data3)
        nrTries = 1
        while true
          begin 
            @agent.page.forms.first.submit
            break
          rescue
            puts "Rescue in submit. nrTries is #{nrTries}. Retry after a few seconds"
            nrTries += 1
            sleep 10
            exit 1 if nrTries > 3
          end
        end
        filename = "#{LogDir}/vereinfachte_detail_#{einfach.firstHit + position}.html"
        writeResponse(filename)
        matchResult = @agent.page.search('h1').text
        unless /Detailansicht zu (Gesuch|Marke)/.match(matchResult)
          puts matchResult
          puts "Attention did not find 'Detailansicht' in #{filename}. Someting went wrong!"
          break
        end
        @results << Swissreg::getMarkenInfoFromDetail(Nokogiri::Slop(@agent.page.body))
        @agent.back
        sleep 1      
      }
      filename = "#{LogDir}/vereinfachte_#{pageNr}_back.html"
      writeResponse(filename)
      if pageNr < (einfach.nrSubPages-1)
          puts "Fetching page #{subPage2Fetch} of #{einfach.nrSubPages}" if $VERBOSE
          Swissreg::setAllInputValue(@agent.page.forms.first, data2)
          @agent.page.forms.first.submit
          getAllHits(nil, subPage2Fetch)
          @agent.back
      end
      
    end

    def fetchresult(filename =  "#{LogDir}/fetch_1.html", counter = 1)
      if filename && File.exists?(filename)
        doc = Nokogiri::Slop(File.open(filename))        
      else
        body = @agent.page.body
        body.force_encoding('utf-8') unless /^1\.8/.match(RUBY_VERSION)
        doc = Nokogiri::Slop(body)
        writeResponse(filename)
      end
      
      if /Vereinfachte Trefferliste anzeigen/i.match(doc.text)
        form = @agent.page.forms.first
        button = form.button_with(:value => /Vereinfachte/i)
        # submit the form using that button
        @agent.submit(form, button)
        filename =  "#{LogDir}/vereinfacht.html"
        writeResponse(filename)
      end
      getAllHits(filename, counter)
    end

  end # class Swissreg

  def Brand2csv::run(timespan, marke = 'a*')
    session = Swissreg.new(timespan, marke)
    begin
      session.parse_swissreg
      session.fetchresult
    rescue Interrupt, Net::HTTP::Persistent::Error
      puts "Unterbrochen. Vesuche #{session.results.size} Resultate zu speichern"
    end
    Swissreg::emitCsv(session.results, "#{timespan}.csv")
  end
  
end # module Brand2csv
