require 'sinatra'
require 'pg'
require 'haml'
require 'sass'
require 'sequel'
require 'tree'
require 'json'
require 'open-uri'

enable :sessions

set :haml, :format => :html5

DB = Sequel.connect('postgres://gaia:Qum$ep13@localhost:5432/gaia')

def find_parent(tree, parent_id)
  tree.each do |node|
    return node if node.name == parent_id
  end
end

def fetch_tag_tree
  tags = DB[:tag].join(:tag_tree, :t_id => :t_id).order(:path)

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
    DB[:tagtype_def].all
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

post '/tags' do
  ptag = params[:tag]

  new_path = DB[:tag_tree].filter(:t_id => ptag[:parent_id]).first[:path] + '.' + ptag[:t_id].to_s

  tag = DB[:tag].filter(:t_id => ptag[:t_id])
  tag_tree = DB[:tag_tree].filter(:t_id => ptag[:t_id])

  if  tag_tree.first[:parent_id] != ptag[:parent_id]
    fix_tree = {
      :original_path => tag_tree.first[:path],
      :new_path      => new_path
    }
  end

  DB.transaction do
    tag.update(
      :title       => ptag[:title], 
      :description => ptag[:description], 
      :ttype_id    => ptag[:ttype_id]
    )
    tag_tree.update(
      :parent_id  => ptag[:parent_id],
      :is_visible => ptag[:is_visible] ? 'true' : 'false',
      :path       => new_path
      )

    if fix_tree
      # for all of the descendants of the moved tag, move them too
      children = DB[:tag_tree].filter("path <@ '#{fix_tree[:original_path]}'")
      children.update("path = text2ltree(regexp_replace(ltree2text(path),'^#{fix_tree[:original_path]}','#{fix_tree[:new_path]}'))")
    end
  end

  session[:flash] = "That update probably worked, you should check."

  puts params.inspect
  redirect "/"
end
