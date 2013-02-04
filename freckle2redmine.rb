require 'bundler'
Bundler.require

require 'active_resource'

FRECKLE_TOKEN = ENV['FRECKLE_TOKEN']
REDMINE_TOKEN = ENV['REDMINE_TOKEN']
DAY = ARGV[0] ? Chronic.parse(ARGV[0], context: :past) : Time.now
REDMINE_HOST = "http://#{REDMINE_TOKEN}:password@redmine.my-company.com"

class FreckleApi < ActiveResource::Base
  self.site = "https://pcreux.letsfreckle.com/api"
end

class Entry < FreckleApi
  self.headers["X-FreckleToken"] = FRECKLE_TOKEN

  def self.on(date)
    find(:all, params: {"search[from]" => date.to_date, "search[to]" => date.to_date})
  end

  def project
    Project.find(project_id)
  end

  def duration
    minutes / 60.0
  end
end

class Project < FreckleApi
  self.headers["X-FreckleToken"] = FRECKLE_TOKEN

  def self.find(project_id)
    @projects ||= {}
    @projects[project_id] ||= super
  end
end

class TimeEntry < ActiveResource::Base
  self.site = REDMINE_HOST

  attr_accessor :freckle_entry

  def billable?
    project_id
  end
end

class EntryBuilder
  def self.build(freckle_entry)
    new(freckle_entry).time_entry
  end

  attr_reader :freckle_entry

  def initialize(freckle_entry)
    @freckle_entry = freckle_entry
  end

  def time_entry
    TimeEntry.new(
      issue_id: issue_id,
      project_id: project_id,
      spent_on: date,
      hours: hours,
      activity_id: activity_id,
      comments: comments
    )
  end

  def issue_id
    freckle_entry.description[/#\d+/].try(:sub, /^#/, '')
  end

  # Freckle project id => Redmine project name
  def project_id
    return nil if issue_id

    case freckle_entry.project_id
    when 128785 # Project EDA
      "eda"
    when 129594 # Internal
      "reverb"
    when 129942 # Project Meh
      "meh"
    when 84716  # Project Wow
      "wow"
    else
      nil
    end
  end

  def date
    freckle_entry.date
  end

  def hours
    freckle_entry.duration
  end

  # Freckle entry description => Redmine activity id
  def activity_id
    case freckle_entry.description
    when /review/i
      DEV
    when /meeting/i
      MEETING
    when /stand ?up/i
      MEETING
    when /merge/i
      DEV
    when /requirement/i
      REQUIREMENTS
    else
      DEV
    end
  end

  def comments
    freckle_entry.description
  end
end

# Redmine activity ids
DEV = 9
DESIGN = 8
MEETING = 12
PM = 10
REQUIREMENTS = 13

entries = Entry.on(DAY).map do |e|
  entry = EntryBuilder.build(e)


  if entry.billable?
    puts "#{entry.spent_on} #{entry.project_id} #{"##{entry.issue_id} " if entry.issue_id}#{entry.hours} #{entry.comments} (#{entry.activity_id})"
    entry
  else
    nil
  end
end.compact

puts "Push?"

if $stdin.gets.chomp == "y"
  entries.map do |entry| 
    puts "."
    entry.save!
  end

  puts "Done!"
end
