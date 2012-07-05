require 'sinatra'
require 'pg'
require 'haml'
require 'sass'
require 'sequel'
require 'tree'

enable :sessions

set :haml, :format => :html5

DB = Sequel.connect('postgres://postgres@localhost:5432/gaia')

def find_parent(tree, parent_id)
  tree.each do |node|
    return node if node.name == parent_id
  end
end

def fetch_tag_tree
  tags = DB["SELECT tt.*, t.title, t.ttype_id, t.description FROM facet.tag_tree AS tt INNER JOIN facet.tag as t ON (tt.t_id = t.t_id) ORDER BY tt.path ASC"]

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
  @flash = session.delete(:flash)
  haml :index
end

post '/tags/:t_id' do
  tag = params[:tag]
  t_id = params[:t_id]

  new_path = DB["SELECT * FROM facet.tag_tree WHERE t_id = #{tag[:parent_id]}"].first[:path] + '.' + t_id.to_s

  query = <<-SQLF
    UPDATE facet.tag SET title = '#{tag[:title]}', description = '#{tag[:description]}', ttype_id = #{tag[:ttype_id]} WHERE t_id = #{t_id};
    UPDATE facet.tag_tree SET parent_id = #{tag[:parent_id]}, is_visible = #{tag[:is_visible] ? 'true' : 'false'}, path = '#{new_path}' WHERE t_id = #{t_id};
  SQLF
  
  if DB.run(query)
    session[:flash] = "Updated Tag #{params[:t_id]}<br />#{query}"
  else
    session[:flash] = "Update Failed (tell Pol, copy/paste the following): #{query}"
  end
  puts params.inspect
  redirect "/"
end
