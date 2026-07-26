package repository

import "go.mongodb.org/mongo-driver/mongo"

type Repositories struct {
	Users         UserRepo
	Chats         ChatRepo
	Messages      MessageRepo
	Posts         PostRepo
	Favorites     FavoriteRepo
	Subscriptions SubscriptionRepo
}

func New(db *mongo.Database) *Repositories {
	if db == nil {
		return &Repositories{}
	}
	return &Repositories{
		Users:         &UserRepository{coll: db.Collection("users")},
		Chats:         &ChatRepository{coll: db.Collection("chats")},
		Messages:      &MessageRepository{coll: db.Collection("messages")},
		Posts:         &PostRepository{coll: db.Collection("posts")},
		Favorites:     &FavoriteRepository{coll: db.Collection("favorites")},
		Subscriptions: &SubscriptionRepository{coll: db.Collection("subscriptions")},
	}
}
