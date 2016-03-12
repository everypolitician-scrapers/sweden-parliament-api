#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'colorize'
require 'pry'
require 'open-uri'

def noko_for(url)
  warn "Fetching #{url}"
  Nokogiri::XML(open(url).read)
end

GENDER = {
  kvinna: 'female',
  man: 'male',
}


def parse_person(p)
  field = ->(n) { p.at_xpath("./#{n}").text.to_s }

  contact = ->(t) { p.xpath(".//personuppgift/uppgift[kod[.='#{t}']]/uppgift").text.to_s }

  data = { 
    id: field.('intressent_id'),
    birth_date: field.('fodd_ar') ,
    gender: GENDER[field.('kon').to_sym],
    name: "%s %s" % [field.('tilltalsnamn'), field.('efternamn')],
    family_name: field.('efternamn'),
    given_name: field.('tilltalsnamn'),
    sort_name: field.('tilltalsnamn'),
    website: contact.('Webbsida'),
    email: contact.('Officiell e-postadress').sub('[på]','@'),
    facebook: p.xpath('.//uppgift/uppgift[contains(.,"facebook")]').text.to_s,
    twitter: p.xpath('.//uppgift/uppgift[contains(.,"twitter")]').text.to_s,
    linkedin: p.xpath('.//uppgift/uppgift[contains(.,"linkedin")]').text.to_s,
    image: field.('bild_url_max'),
    source: field.('person_url_xml'),
  }
  if field.('status').match(/Avliden\s+(\d{4}-\d{2}-\d{2})/)
    data[:death_date] = $1
  end

  party = field.('parti') 
  constituency = field.('valkrets')

  mem_info = { 
    'Tjänstgörande' => p.xpath('./personuppdrag//uppdrag[roll_kod="Riksdagsledamot"]'),
    'Ersättare' => p.xpath('./personuppdrag//uppdrag[roll_kod="Ersättare"]')
  }

  mem_info.each do |type, mems|
    mems.each do |mem|
      mfield = ->(n) { mem.at_xpath("./#{n}").text.to_s }
      next unless mfield.('status') == type
      rec = { 
        start_date: mfield.('from'),
        end_date: mfield.('tom'),
      }
      next if rec[:start_date] < @terms.first[:start_date]

      rec[:substitute] = mfield.('uppgift') if type == 'Ersättare'
      unless rec[:term] = term_for(rec) 
        warn("Invalid dates: #{rec}") 
        next
      end

      row = data.merge(rec)
      # warn row
      ScraperWiki.save_sqlite([:id, :term, :start_date], data.merge(row))
    end
  end
end

def term_for(mem)
  term = @terms.find { |t| mem[:start_date] <= t[:end_date] && mem[:end_date] >= t[:start_date] } or return
  term[:id]
end


term_dates = %w( 1976-10-04
  1979-10-01 1982-10-04 1985-09-30 1988-10-03
  1991-09-30 1994-10-03 1998-10-05 2002-09-30
  2006-10-02 2010-10-04 2014-09-29 2018-09-24
)

@terms = term_dates.each_cons(2).map { |s, e|
  { 
    id: s[0..3],
    name: '%s–%s' % [s[0..3], e[0..3]],
    start_date: s,
    end_date: e,
  }
}
ScraperWiki.save_sqlite([:id], @terms, 'terms')

xml_file = 'formatted.xml'
noko = noko_for('http://data.riksdagen.se/personlista/?iid=&fnamn=&enamn=&f_ar=&kn=&parti=&valkrets=&rdlstatus=samtliga&org=&utformat=xml&termlista=')
noko.xpath('//person').each { |p| parse_person(p) }

