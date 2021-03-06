#!/usr/bin/env ruby

Encoding.default_external = Encoding::UTF_8
require 'erb'
require 'yaml'
require 'nokogiri'
require 'open_uri_redirections'
require 'time'
require 'json'

COMPANY_NOT_FOUND='not_found'
COMPANY_NOT_DEFINED='not_defined'
UPDATE_NONE=0
UPDATE_NOT_FOUND=1
UPDATE_ALL=2

name_variants = Hash.new(0)
Dir.mkdir('../data') unless Dir.exist?('../data')
if File.exists? ('../data/company_infos.yml')
  companies_info = YAML::load_file('../data/company_infos.yml')
else
  companies_info = Hash.new(0)
end
if File.exists? ('../data/company_mapping.yml')
  company_mapping = YAML::load_file('../data/company_mapping.yml') || Hash.new(0)
else
  company_mapping = Hash.new(0)
end
update=UPDATE_NONE
if ARGV.length == 1
  if ARGV[0] == '--update-all'
    update=UPDATE_ALL
  else
    if ARGV[0] == '--update-not-found'
      update=UPDATE_NOT_FOUND
    end
  end
end

i = 1;
lastOrder = -1;
lastMentions = 0;
file = file = File.read('../../tmp/data.json')
data = JSON.parse(file)
contributors = data['contributors']
companies = Hash.new(0)

def ensure_company(companies, companies_info, key, title, link)
  unless companies.key? key
    companies[key] = Hash.new(0)
    companies[key]['contributors'] = Hash.new(0)
    if companies_info.key? key
      companies[key]['title'] = companies_info[key]['title']
      companies[key]['link'] = companies_info[key]['link']
    else
      companies[key]['title'] = title
      companies[key]['link'] = link
    end
  end
end

contributors.sort_by {|k, v| v }.reverse.each do |name,mentions|
  if company_mapping.key? name
    if update == UPDATE_NONE or (update == UPDATE_NOT_FOUND and company_mapping[name] != COMPANY_NOT_FOUND)
      ensure_company(companies, companies_info, company_mapping[name], 'should be filled via company infos', 'should be filled via company infos')
      companies[company_mapping[name]]['mentions'] += mentions
      companies[company_mapping[name]]['contributors'][name] = mentions
      next
    end
  end
  if name_variants.key? name
    urlname = name_variants[name].gsub ' ', '-';
  else
    urlname = name.gsub ' ', '-';
  end
  url = "https://www.drupal.org/u/#{urlname}"
  url = URI::encode(url)
  begin
    html = open(url, :allow_redirections => :safe)
    doc = Nokogiri::HTML(html)
  rescue
    next
  end
  found = true
  doc.css('title').each do |title|
    if title.text == 'Page not found | Drupal.org'
      found = false
    end
  end
  unless found
    ensure_company(companies, companies_info, COMPANY_NOT_FOUND, 'Users not found', 'Users not found')
    companies[COMPANY_NOT_FOUND]['mentions'] += mentions
    companies[COMPANY_NOT_FOUND]['contributors'][name] = mentions
  end
  if found
    found = false
    if company_wrapper = doc.at_css('.field-name-field-organization-name')
      if company_wrapper.at_css('img')
        company = company_wrapper.at_css('img')['alt']
      else
        company = company_wrapper.text
      end
      if company_wrapper.at_css('a')
        link = company_wrapper.at_css('a')
        link['href'] = 'https://drupal.org' + link['href']
        # If we still don't have the company name, follow the link to the page.
        unless company
          html = open(link['href'], :allow_redirections => :safe)
          company_page = Nokogiri::HTML(html)
          if company_title  = company_page.at_css('#page-subtitle')
            company = company_title.text
          end
        end
      else
        # If there is no link, use the company name instead.
        link = company
      end
      company = company.strip
      company_key = company.downcase
      ensure_company(companies, companies_info, company_key, company, link.to_s)
      companies[company_key]['mentions'] += mentions
      companies[company_key]['contributors'][name] = mentions
      found = true
    end
    unless found
      ensure_company(companies, companies_info, COMPANY_NOT_DEFINED, 'Not specified', 'Not specified')
      companies[COMPANY_NOT_DEFINED]['mentions'] += mentions
      companies[COMPANY_NOT_DEFINED]['contributors'][name] = mentions
    end
  end
end

companies = companies.sort_by {|k, v| v['mentions'] }.reverse
companies.each do |k, values|
  unless companies_info.key? k
    companies_info[k] = Hash.new(0)
    companies_info[k]['title'] = values['title']
    companies_info[k]['link'] = values['link']
  end
  values['contributors'].each do |name, mentions|
    company_mapping[name] = k
  end
  if values['contributors'].length == 0
    companies_info.delete(k)
  end
end
File.open('../data/company_infos.yml', 'w') { |f| YAML.dump(companies_info, f) }
File.open('../data/company_mapping.yml', 'w') { |f| YAML.dump(company_mapping, f) }

sum = contributors.values.reduce(:+).to_f
puts ERB.new(DATA.readlines.join, 0, '>').result

time = Time.now()
description = "A simple table of all contributors to Drupal 8 core"
header = ERB.new(File.new("../templates/partials/header.html.erb").read).result(binding)
footer = ERB.new(File.new("../templates/partials/footer.html.erb").read).result(binding)
companies_template = File.open("../templates/companies.html.erb", 'r').read
renderer = ERB.new(companies_template)
puts output = renderer.result()

__END__
