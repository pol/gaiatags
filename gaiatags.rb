require 'sinatra'
require 'pg'
require 'haml'
require 'sass'
require 'sequel'
require 'tree'

set :haml, :format => :html5

DB = Sequel.connect('postgres://postgres@localhost:5432/gaia')

def find_parent(tree, parent_id)
  tree.each do |node|
    return node if node.name == parent_id
  end
end

def fetch_tag_tree
  tags = DB["SELECT tt.*, t.title, t.ttype_id, t.description FROM facet.tag_tree AS tt INNER JOIN facet.tag as t ON (tt.t_id = t.t_id) ORDER BY tt.t_id ASC"]

  tree = Tree::TreeNode.new(0, 'Gaia Tags')

  tags.each do |tag|
    node = Tree::TreeNode.new(tag[:t_id], tag)
    if tag[:parent_id].nil?
      tree = node
    else
      parent = find_parent(tree, tag[:parent_id])
      parent << node
    end
  end
  tree
end

helpers do 

  def tag_types
    DB["SELECT * from facet.tagtype_def"].all
  end

  def print_tree(tree)
    output = "<li><span class='o#{tree.node_depth} v#{tree.content[:is_visible]}'>#{tree.name} : #{tree.content[:title]}</span>"
    output += " <span onClick=\"$('#edit_tag_#{tree.content[:t_id]}').toggle();\">[e]</span>"
    output += haml :edit_tag, :locals => {:tag => tree.content, :tagtypes => tag_types }
    unless tree.children.empty?
      output += "<ul class='o#{tree.node_depth + 1}'>"
      tree.children.each do |c|
        output += print_tree(c)
      end
      output += "</ul>\n"
    end
    output += "</li>\n"
    output
  end
end

get '/' do 
  @tag_tree = fetch_tag_tree
  haml :index
end