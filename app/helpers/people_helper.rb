module PeopleHelper
  
  def expertises_as_comma_seperated_list expertises
    res=""
    expertises.each do |exp|
      res << exp.name
      res << ", " unless (expertises.last==exp)
    end
    return res
  end
  
  def person_list_item_extra_details? person
    !(person.projects.empty? and person.institutions.empty?)  
  end
  
end
