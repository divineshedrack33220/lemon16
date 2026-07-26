package models

import "go.mongodb.org/mongo-driver/bson/primitive"

type PushSubscription struct {
	ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	UserID    primitive.ObjectID `bson:"userId" json:"userId"`
	Endpoint  string             `bson:"endpoint" json:"endpoint"`
	Keys      PushKeys           `bson:"keys" json:"keys"`
	CreatedAt int64              `bson:"createdAt" json:"createdAt"`
}

type PushKeys struct {
	P256dh string `bson:"p256dh" json:"p256dh"`
	Auth   string `bson:"auth" json:"auth"`
}
